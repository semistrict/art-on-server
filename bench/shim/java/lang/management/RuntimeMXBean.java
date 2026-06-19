package java.lang.management;

import java.util.List;

// Minimal shim: Android/ART omits java.lang.management, but the core JMH runner references a small
// slice of it (to record the JVM input arguments and name in the result header). Placed on the ART
// bootclasspath because the runtime forbids app classloaders from defining java.* classes.
public interface RuntimeMXBean {
  List<String> getInputArguments();

  String getName();
}
