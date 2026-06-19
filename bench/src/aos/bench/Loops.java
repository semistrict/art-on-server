package aos.bench;

import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Warmup;
import org.openjdk.jmh.infra.Blackhole;

// Feasibility probe: the simplest possible JMH benchmark, used to confirm the JMH harness runs
// in-process (@Fork(0)) on ART as well as on the JVM. Fork(0) is required because JMH's forked
// mode builds a `java`-style command line, which ART's dalvikvm launcher does not accept.
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@State(Scope.Thread)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(0)
public class Loops {

  @Benchmark
  public long intSum() {
    long s = 0;
    for (int i = 0; i < 100_000; i++) {
      s += i;
    }
    return s;
  }

  @Benchmark
  public void consume(Blackhole bh) {
    for (int i = 0; i < 1_000; i++) {
      bh.consume(i * 31 + 7);
    }
  }
}
