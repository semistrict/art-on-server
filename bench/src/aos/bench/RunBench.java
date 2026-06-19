package aos.bench;

import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.options.ChainedOptionsBuilder;
import org.openjdk.jmh.runner.options.OptionsBuilder;

// In-process JMH entry point shared by the JVM and ART runs. ART cannot be forked by JMH (its
// dalvikvm launcher is not a `java`-compatible CLI), so everything runs with forks=0 in the
// launching runtime; the JVM run uses the same forks=0 for an identical methodology. Pass include
// regexes as args (default: all). Results are emitted as text and, if -rf/-rff are honored, files.
public final class RunBench {
  public static void main(String[] args) throws Exception {
    ChainedOptionsBuilder b = new OptionsBuilder().forks(0);
    boolean haveInclude = false;
    for (String a : args) {
      if (a.startsWith("-rff=")) {
        b.resultFormat(org.openjdk.jmh.results.format.ResultFormatType.CSV);
        b.result(a.substring("-rff=".length()));
      } else {
        b.include(a);
        haveInclude = true;
      }
    }
    if (!haveInclude) {
      b.include(".*");
    }
    new Runner(b.build()).run();
  }
}
