package z9;

import android.content.ComponentName;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import com.android.uiautomator.testrunner.UiAutomatorTestCase;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

public class SetLauncherDefaultBinderTest extends UiAutomatorTestCase {
    public void testSetEInkAsPermanentHome() throws Exception {
        Class<?> serviceManager = Class.forName("android.os.ServiceManager");
        Method getService = serviceManager.getDeclaredMethod("getService", String.class);
        getService.setAccessible(true);
        Object binder = getService.invoke(null, "package");
        Class<?> pmInterface = Class.forName("android.content.pm.IPackageManager");
        Class<?> stub = Class.forName("android.content.pm.IPackageManager$Stub");
        Method asInterface = stub.getDeclaredMethod("asInterface", Class.forName("android.os.IBinder"));
        asInterface.setAccessible(true);
        Object pm = asInterface.invoke(null, binder);
        Method clearSarkBookDefault = pmInterface.getMethod("clearPackagePreferredActivities", String.class);
        clearSarkBookDefault.invoke(pm, "com.smart.arkbook");
        System.out.println("Z9_CLEARED_PREFERRED_ACTIVITIES=com.smart.arkbook");

        Intent home = new Intent(Intent.ACTION_MAIN);
        home.addCategory(Intent.CATEGORY_HOME);
        Method query = pmInterface.getMethod("queryIntentActivities", Intent.class, String.class, int.class, int.class);
        Object slice = query.invoke(pm, home, null, PackageManager.MATCH_DEFAULT_ONLY, 0);
        System.out.println("Z9_QUERY_RESULT_CLASS=" + slice.getClass().getName());
        List<?> results;
        if (slice instanceof List) {
            results = (List<?>) slice;
        } else {
            Method getList = null;
            for (Method method : slice.getClass().getDeclaredMethods()) if ("getList".equals(method.getName())) getList = method;
            if (getList == null) {
                for (Method method : slice.getClass().getDeclaredMethods()) System.out.println("Z9_QUERY_RESULT_METHOD=" + method.getName());
                throw new AssertionError("Could not extract query result list");
            }
            getList.setAccessible(true);
            results = (List<?>) getList.invoke(slice);
        }
        ArrayList<ComponentName> candidates = new ArrayList<ComponentName>();
        ResolveInfo eink = null;
        for (Object object : results) {
            ResolveInfo result = (ResolveInfo) object;
            if (result.activityInfo == null) continue;
            ComponentName component = new ComponentName(result.activityInfo.packageName, result.activityInfo.name);
            candidates.add(component);
            System.out.println("Z9_HOME_CANDIDATE=" + component.flattenToShortString() + " MATCH=" + result.match);
            if ("cn.modificator.launcher".equals(result.activityInfo.packageName)) eink = result;
        }
        if (eink == null || candidates.size() < 2) throw new AssertionError("E-Ink HOME candidate missing or resolver set incomplete");

        IntentFilter filter = new IntentFilter(Intent.ACTION_MAIN);
        filter.addCategory(Intent.CATEGORY_HOME);
        filter.addCategory(Intent.CATEGORY_DEFAULT);
        ComponentName target = new ComponentName(eink.activityInfo.packageName, eink.activityInfo.name);
        Method addPreferred = pmInterface.getMethod("addPreferredActivity", IntentFilter.class, int.class, ComponentName[].class, ComponentName.class, int.class);
        addPreferred.invoke(pm, filter, eink.match, candidates.toArray(new ComponentName[candidates.size()]), target, 0);
        System.out.println("Z9_PREFERRED_SET=" + target.flattenToShortString());

        Method resolve = pmInterface.getMethod("resolveIntent", Intent.class, String.class, int.class, int.class);
        ResolveInfo chosen = (ResolveInfo) resolve.invoke(pm, home, null, PackageManager.MATCH_DEFAULT_ONLY, 0);
        String resolved = chosen == null || chosen.activityInfo == null ? "NONE"
                : new ComponentName(chosen.activityInfo.packageName, chosen.activityInfo.name).flattenToShortString();
        System.out.println("Z9_HOME_RESOLVES_TO=" + resolved);
        if (!target.equals(chosen == null || chosen.activityInfo == null ? null
                : new ComponentName(chosen.activityInfo.packageName, chosen.activityInfo.name))) {
            throw new AssertionError("E-Ink was not selected as HOME: " + resolved);
        }
    }
}
