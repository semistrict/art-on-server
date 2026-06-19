package java.lang.management;

// Minimal shim (see RuntimeMXBean). JMH's BaseRunner reads getCollectionCount() off the GC beans to
// report GC churn between iterations; with an empty bean list (see ManagementFactory) it is never
// called, but the type must exist for the checkcast in that loop.
public interface GarbageCollectorMXBean {
  long getCollectionCount();
}
