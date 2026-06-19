package java.lang.management;

import java.util.Collections;
import java.util.List;

// Minimal shim (see RuntimeMXBean). Supplies just the static factory methods the core JMH runner
// calls. getInputArguments() is empty (we pass JVM/ART flags on the launcher command line, not via
// this bean) and the GC bean list is empty (GC-delta reporting is skipped, which is fine for a
// throughput comparison). getName() returns a stable placeholder of the form "<pid>@<host>".
public final class ManagementFactory {

  private ManagementFactory() {}

  public static RuntimeMXBean getRuntimeMXBean() {
    return new RuntimeMXBean() {
      @Override
      public List<String> getInputArguments() {
        return Collections.emptyList();
      }

      @Override
      public String getName() {
        // Format is "<pid>@<host>"; JMH only records it, so a stable placeholder is fine.
        return "0@art";
      }
    };
  }

  public static List<GarbageCollectorMXBean> getGarbageCollectorMXBeans() {
    return Collections.emptyList();
  }
}
