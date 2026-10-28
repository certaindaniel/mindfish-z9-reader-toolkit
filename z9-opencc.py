#!/usr/bin/env python3
"""Create Taiwan Traditional Chinese copies of EPUB and TXT books.

OpenCC runs on the host Mac. For a device path, this script transfers the
source over ADB, converts it, uploads a temporary file, checks its checksum,
and renames it beside the original without replacing the original or an
existing converted copy.
"""

from __future__ import annotations

import argparse
import codecs
import copy
import hashlib
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path, PurePosixPath
from typing import Iterable


CONFIG = "s2twp"
TEXT_EXTENSIONS = {".html", ".htm", ".ncx", ".opf", ".svg", ".xhtml", ".xml"}
MAX_MARKUP_BYTES = 32 * 1024 * 1024
MAX_TXT_BYTES = 256 * 1024 * 1024
MIMETYPE_CONTENT = b"application/epub+zip"


class ConversionError(Exception):
    pass


def _run_opencc(opencc: str, text: str) -> str:
    if "\x00" in text:
        raise ConversionError("文字內容含有 NUL 位元組，無法安全交給 OpenCC。")
    guard = f"__Z9_OPENCC_GUARD_{uuid.uuid4().hex}__"
    while guard in text:
        guard = f"__Z9_OPENCC_GUARD_{uuid.uuid4().hex}__"
    try:
        result = subprocess.run(
            [opencc, "-c", CONFIG],
            input=(guard + text + guard).encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        raise ConversionError(f"無法啟動 OpenCC：{exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ConversionError(f"OpenCC 轉換失敗：{detail or result.returncode}")
    try:
        converted = result.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ConversionError("OpenCC 輸出不是有效的 UTF-8。") from exc
    if not converted.startswith(guard) or not converted.endswith(guard):
        raise ConversionError("OpenCC 輸出完整性標記不符，已取消輸出。")
    return converted[len(guard) : -len(guard)]


def _markup_end(text: str, start: int, declaration: bool = False) -> int:
    quote = None
    bracket_depth = 0
    for index in range(start + 1, len(text)):
        char = text[index]
        if quote:
            if char == quote:
                quote = None
        elif char in ("'", '"'):
            quote = char
        elif declaration and char == "[":
            bracket_depth += 1
        elif declaration and char == "]" and bracket_depth:
            bracket_depth -= 1
        elif char == ">" and bracket_depth == 0:
            return index + 1
    return len(text)


def _numeric_cjk_entities(text: str) -> str:
    entity = re.compile(r"&#(?:([0-9]+)|[xX]([0-9a-fA-F]+));")

    def replace(match: re.Match[str]) -> str:
        codepoint = int(match.group(1), 10) if match.group(1) else int(match.group(2), 16)
        if (
            0x3400 <= codepoint <= 0x4DBF
            or 0x4E00 <= codepoint <= 0x9FFF
            or 0xF900 <= codepoint <= 0xFAFF
            or 0x20000 <= codepoint <= 0x3134F
        ):
            return chr(codepoint)
        return match.group(0)

    return entity.sub(replace, text)


def _markup_segments(text: str) -> list[tuple[str, bool]]:
    """Split markup into (text, is_visible_character_data) segments."""
    parts: list[tuple[str, bool]] = []
    position = 0
    raw_tag: str | None = None

    while position < len(text):
        if raw_tag:
            closing = re.search(r"</\s*" + re.escape(raw_tag) + r"\s*[^>]*>", text[position:], re.I)
            if not closing:
                parts.append((text[position:], False))
                break
            start = position + closing.start()
            end = position + closing.end()
            parts.append((text[position:start], False))
            parts.append((text[start:end], False))
            position = end
            raw_tag = None
            continue

        opening = text.find("<", position)
        if opening < 0:
            parts.append((text[position:], True))
            break
        if opening > position:
            parts.append((text[position:opening], True))
            position = opening

        if text.startswith("<!--", position):
            end = text.find("-->", position + 4)
            end = len(text) if end < 0 else end + 3
            parts.append((text[position:end], False))
            position = end
            continue
        if text.startswith("<![CDATA[", position):
            end = text.find("]]>", position + 9)
            end = len(text) if end < 0 else end + 3
            parts.append((text[position:end], False))
            position = end
            continue
        if text.startswith("<?", position):
            end = text.find("?>", position + 2)
            end = len(text) if end < 0 else end + 2
            parts.append((text[position:end], False))
            position = end
            continue

        # A less-than sign followed by ordinary punctuation is text in HTML.
        following = text[position + 1 : position + 2]
        if following and not (following.isascii() and (following.isalpha() or following in "/!")):
            parts.append(("<", True))
            position += 1
            continue

        declaration = text.startswith("<!", position)
        end = _markup_end(text, position, declaration)
        token = text[position:end]
        parts.append((token, False))
        position = end

        tag_match = re.match(r"<\s*([A-Za-z][A-Za-z0-9:-]*)\b", token)
        if tag_match and not token.startswith("</") and not token.rstrip().endswith("/>"):
            tag_name = tag_match.group(1).lower()
            if tag_name in {"script", "style"}:
                raw_tag = tag_name

    return parts


def _convert_markup(data: bytes, opencc: str, name: str) -> bytes:
    if len(data) > MAX_MARKUP_BYTES:
        raise ConversionError(f"EPUB 文字檔過大，為避免記憶體不足而停止：{name}")
    has_bom = data.startswith(codecs.BOM_UTF8)
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ConversionError(f"EPUB 文字檔不是 UTF-8，無法安全轉換：{name}") from exc

    parts = _markup_segments(text)
    convertible_indices = [i for i, (part, visible) in enumerate(parts) if visible and part]
    if not convertible_indices:
        return data

    visible_parts = [_numeric_cjk_entities(parts[i][0]) for i in convertible_indices]
    marker = f"__Z9_OPENCC_{uuid.uuid4().hex}__"
    while marker in text:
        marker = f"__Z9_OPENCC_{uuid.uuid4().hex}__"
    joined = marker + marker.join(visible_parts) + marker
    converted = _run_opencc(opencc, joined)
    split = converted.split(marker)
    if len(split) != len(visible_parts) + 2 or split[0] or split[-1]:
        raise ConversionError(f"OpenCC 分隔符驗證失敗，已取消輸出：{name}")

    for part_index, result in zip(convertible_indices, split[1:-1]):
        parts[part_index] = (result, True)
    converted_text = "".join(part for part, _visible in parts)
    return (codecs.BOM_UTF8 if has_bom else b"") + converted_text.encode("utf-8")


def _decode_txt(data: bytes) -> tuple[str, bytes, str]:
    for bom, encoding, name, decode_bom in (
        (codecs.BOM_UTF32_LE, "utf-32-le", "UTF-32 LE", False),
        (codecs.BOM_UTF32_BE, "utf-32-be", "UTF-32 BE", False),
        (codecs.BOM_UTF8, "utf-8-sig", "UTF-8", True),
        (codecs.BOM_UTF16_LE, "utf-16-le", "UTF-16 LE", False),
        (codecs.BOM_UTF16_BE, "utf-16-be", "UTF-16 BE", False),
    ):
        if data.startswith(bom):
            try:
                payload = data if decode_bom else data[len(bom) :]
                return payload.decode(encoding), bom, name
            except UnicodeDecodeError as exc:
                raise ConversionError(f"TXT 編碼標記為 {name}，但內容無法解碼。") from exc
    try:
        return data.decode("utf-8"), b"", "UTF-8"
    except UnicodeDecodeError as exc:
        raise ConversionError("TXT 不是 UTF-8，也沒有可辨識的 BOM；請先轉成 UTF-8。") from exc


def _convert_txt(source: Path, destination: Path, opencc: str) -> None:
    if source.stat().st_size > MAX_TXT_BYTES:
        raise ConversionError(f"TXT 超過 {MAX_TXT_BYTES // (1024 * 1024)} MiB，已停止以避免記憶體不足。")
    data = source.read_bytes()
    text, bom, encoding_name = _decode_txt(data)
    converted = _run_opencc(opencc, text)
    try:
        destination.write_bytes(bom + converted.encode(encoding_name.lower().replace(" ", "-")))
    except (LookupError, UnicodeEncodeError) as exc:
        raise ConversionError(f"轉換後無法以原始 {encoding_name} 編碼儲存。") from exc


def _is_convertible_text(name: str) -> bool:
    return PurePosixPath(name).suffix.lower() in TEXT_EXTENSIONS


def _convert_epub(source: Path, destination: Path, opencc: str) -> tuple[int, int]:
    converted_files = 0
    text_files = 0
    try:
        with zipfile.ZipFile(source, "r") as original:
            infos = original.infolist()
            names = [info.filename for info in infos]
            if len(names) != len(set(names)):
                raise ConversionError("EPUB 含有重複的 ZIP 檔名，為避免遺失內容而停止。")
            mimetype_infos = [info for info in infos if info.filename == "mimetype"]
            if len(mimetype_infos) != 1 or original.read(mimetype_infos[0]) != MIMETYPE_CONTENT:
                raise ConversionError("這不是有效的 EPUB：缺少正確的 mimetype 項目。")
            if not any(name.lower().endswith(".opf") for name in names):
                raise ConversionError("EPUB 缺少 OPF 封裝文件，已停止。")

            ordered = [mimetype_infos[0]] + [info for info in infos if info.filename != "mimetype"]
            with zipfile.ZipFile(destination, "w", allowZip64=True) as converted:
                converted.comment = original.comment
                for info in ordered:
                    output_info = copy.copy(info)
                    if info.filename == "mimetype":
                        output_info.compress_type = zipfile.ZIP_STORED
                        output_info.extra = b""
                        converted.writestr(output_info, MIMETYPE_CONTENT, compress_type=zipfile.ZIP_STORED)
                    elif info.is_dir():
                        converted.writestr(output_info, b"", compress_type=output_info.compress_type)
                    elif _is_convertible_text(info.filename):
                        payload = original.read(info)
                        text_files += 1
                        converted_payload = _convert_markup(payload, opencc, info.filename)
                        if converted_payload != payload:
                            converted_files += 1
                        converted.writestr(output_info, converted_payload, compress_type=output_info.compress_type)
                    else:
                        # Stream images, fonts, and other binary entries to keep
                        # peak memory use bounded on large books.
                        with original.open(info, "r") as src_entry:
                            with converted.open(output_info, "w", force_zip64=True) as dst_entry:
                                shutil.copyfileobj(src_entry, dst_entry, length=1024 * 1024)

        with zipfile.ZipFile(destination, "r") as check:
            check_infos = check.infolist()
            if not check_infos or check_infos[0].filename != "mimetype":
                raise ConversionError("新 EPUB 的 mimetype 順序不正確，已取消輸出。")
            if check_infos[0].compress_type != zipfile.ZIP_STORED:
                raise ConversionError("新 EPUB 的 mimetype 必須未壓縮，已取消輸出。")
            damaged = check.testzip()
            if damaged:
                raise ConversionError(f"新 EPUB 完整性檢查失敗：{damaged}")
    except Exception as exc:
        if isinstance(exc, ConversionError):
            raise
        raise ConversionError(f"EPUB 讀寫失敗，原檔未更動：{exc}") from exc
    return text_files, converted_files


def _converted_name(name: str) -> str:
    path = PurePosixPath(name)
    return str(path.with_name(f"{path.stem}.zh-TW{path.suffix}"))


def _local_converted_path(source: Path) -> Path:
    return source.with_name(f"{source.stem}.zh-TW{source.suffix}")


def _make_temp_path(destination: Path) -> Path:
    fd, raw_path = tempfile.mkstemp(prefix=f".{destination.name}.", suffix=".partial", dir=destination.parent)
    os.close(fd)
    return Path(raw_path)


def _publish_without_overwrite(temporary: Path, destination: Path) -> None:
    os.chmod(temporary, 0o644)
    try:
        os.link(temporary, destination)
    except FileExistsError as exc:
        raise ConversionError(f"輸出檔已存在，沒有覆寫：{destination}") from exc
    except OSError:
        # Some external filesystems disallow hard links. Exclusive creation
        # still prevents replacing an existing file.
        created = False
        try:
            with destination.open("xb") as target:
                created = True
                with temporary.open("rb") as source:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
        except FileExistsError as exc:
            raise ConversionError(f"輸出檔已存在，沒有覆寫：{destination}") from exc
        except OSError:
            if created:
                destination.unlink(missing_ok=True)
            raise
    finally:
        temporary.unlink(missing_ok=True)


def _find_opencc(requested: str | None) -> str:
    candidate = requested or shutil.which("opencc")
    if not candidate:
        raise ConversionError("找不到 OpenCC。Mac 可執行：brew install opencc")
    try:
        result = subprocess.run([candidate, "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except OSError as exc:
        raise ConversionError(f"OpenCC 無法啟動：{exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ConversionError(f"OpenCC 無法啟動：{detail or candidate}")
    return candidate


def _device_serial(adb: str, requested: str | None) -> str:
    try:
        result = subprocess.run([adb, "devices"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    except OSError as exc:
        raise ConversionError(f"無法啟動 adb：{exc}") from exc
    if result.returncode != 0:
        raise ConversionError(f"adb devices 失敗：{result.stderr.strip()}")
    online = [line.split()[0] for line in result.stdout.splitlines()[1:] if len(line.split()) >= 2 and line.split()[1] == "device"]
    if requested:
        if requested not in online:
            raise ConversionError(f"指定的 ADB 裝置未連線：{requested}")
        return requested
    if len(online) != 1:
        raise ConversionError(f"ADB 目前有 {len(online)} 台可用裝置；請用 --serial 指定其中一台。")
    return online[0]


def _adb(adb: str, serial: str, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            [adb, "-s", serial, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False
        )
    except OSError as exc:
        raise ConversionError(f"無法啟動 adb：{exc}") from exc
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ConversionError(f"ADB 指令失敗：{detail}")
    return result


def _convert_device_path(device_path: str, adb: str, serial: str | None, opencc: str) -> Path:
    remote_source = PurePosixPath(device_path)
    if not remote_source.is_absolute() or remote_source.name in {"", ".", ".."}:
        raise ConversionError("裝置路徑必須是完整路徑，例如 /storage/emulated/0/Books/book.epub。")
    suffix = remote_source.suffix.lower()
    if suffix not in {".epub", ".txt"}:
        raise ConversionError("目前只支援 EPUB 與 TXT。")
    remote_output = PurePosixPath(_converted_name(str(remote_source)))
    active_serial = _device_serial(adb, serial)
    output_check = _adb(adb, active_serial, "shell", f"test ! -e {shlex.quote(str(remote_output))}", check=False)
    if output_check.returncode != 0:
        raise ConversionError(f"裝置上的輸出檔已存在，沒有覆寫：{remote_output}")

    with tempfile.TemporaryDirectory(prefix="z9-opencc-") as directory:
        work = Path(directory)
        local_source = work / remote_source.name
        _adb(adb, active_serial, "pull", str(remote_source), str(local_source))
        local_output = work / _converted_name(remote_source.name)
        temporary = _make_temp_path(local_output)
        remote_temp = remote_output.with_name(f".{remote_output.name}.opencc-{uuid.uuid4().hex}.tmp")
        upload_attempted = False
        published_ok = False
        try:
            _convert_file(local_source, temporary, opencc)
            expected_hash = _sha256(temporary)
            upload_attempted = True
            _adb(adb, active_serial, "push", str(temporary), str(remote_temp))

            pulled_back = work / "device-readback"
            _adb(adb, active_serial, "pull", str(remote_temp), str(pulled_back))
            if _sha256(pulled_back) != expected_hash:
                raise ConversionError("裝置回讀的檔案校驗碼不符，已取消重新命名。")

            publish = _adb(
                adb,
                active_serial,
                "shell",
                f"test ! -e {shlex.quote(str(remote_output))} && mv {shlex.quote(str(remote_temp))} {shlex.quote(str(remote_output))}",
                check=False,
            )
            if publish.returncode != 0:
                raise ConversionError(f"裝置上重新命名失敗：{remote_output}")
            published = _adb(
                adb,
                active_serial,
                "shell",
                f"test -f {shlex.quote(str(remote_output))} && test ! -e {shlex.quote(str(remote_temp))}",
                check=False,
            )
            if published.returncode != 0:
                raise ConversionError(f"裝置上的正式輸出檔未通過讀回確認：{remote_output}")
            published_ok = True
        finally:
            if upload_attempted and not published_ok:
                try:
                    cleanup = _adb(
                        adb,
                        active_serial,
                        "shell",
                        f"rm -f {shlex.quote(str(remote_temp))}",
                        check=False,
                    )
                except ConversionError:
                    print(f"無法清除裝置暫存檔：{remote_temp}", file=sys.stderr)
                else:
                    if cleanup.returncode != 0:
                        print(f"無法清除裝置暫存檔：{remote_temp}", file=sys.stderr)
            temporary.unlink(missing_ok=True)
    return Path(str(remote_output))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _convert_file(source: Path, temporary: Path, opencc: str) -> None:
    suffix = source.suffix.lower()
    if suffix == ".txt":
        _convert_txt(source, temporary, opencc)
        return
    if suffix == ".epub":
        text_files, changed_files = _convert_epub(source, temporary, opencc)
        print(f"EPUB 文字文件：{text_files} 個；實際有變更：{changed_files} 個")
        return
    raise ConversionError("目前只支援 EPUB 與 TXT。")


def _convert_local(source_arg: str, opencc: str) -> Path:
    source = Path(source_arg).expanduser().resolve()
    if not source.is_file():
        raise ConversionError(f"找不到來源檔：{source}")
    if source.suffix.lower() not in {".epub", ".txt"}:
        raise ConversionError("目前只支援 EPUB 與 TXT。")
    destination = _local_converted_path(source)
    if destination.exists():
        raise ConversionError(f"輸出檔已存在，沒有覆寫：{destination}")
    temporary = _make_temp_path(destination)
    try:
        _convert_file(source, temporary, opencc)
        _publish_without_overwrite(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    return destination


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="以 OpenCC s2twp 建立 EPUB／TXT 台灣繁體副本。")
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument("--device", metavar="PATH", help="從已連線的 Android 裝置轉換指定路徑")
    source_group.add_argument("source", nargs="?", help="轉換 Mac 上的 EPUB 或 TXT 檔案")
    parser.add_argument("--serial", help="ADB 裝置序號；未指定時要求剛好連線一台")
    parser.add_argument("--adb", default=shutil.which("adb") or "adb", help="adb 執行檔路徑")
    parser.add_argument("--opencc", help="OpenCC 執行檔路徑；預設使用 PATH 中的 opencc")
    args = parser.parse_args(argv)

    try:
        opencc = _find_opencc(args.opencc)
        if args.device:
            output = _convert_device_path(args.device, args.adb, args.serial, opencc)
        else:
            output = _convert_local(args.source, opencc)
        print(f"完成：{output}")
        print("原書保留；繁體副本另存為 .zh-TW。")
        return 0
    except ConversionError as exc:
        print(f"錯誤：{exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
