package aos.bench;

import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Warmup;

// Virtual + interface dispatch over a polymorphic array. Exercises klass loads, vtable/IMT
// dispatch, and inline-cache behaviour -- exactly the reference-load paths the 64-bit work touched.
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@State(Scope.Thread)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(0)
public class Dispatch {

  interface Op {
    long apply(long x);
  }

  static final class Add implements Op {
    public long apply(long x) { return x + 3; }
  }

  static final class Mul implements Op {
    public long apply(long x) { return x * 5 + 1; }
  }

  static final class Xor implements Op {
    public long apply(long x) { return (x ^ (x >>> 7)) + 2; }
  }

  private Op[] ops;
  private Op mono;

  @Setup
  public void setup() {
    ops = new Op[3072];
    for (int i = 0; i < ops.length; i++) {
      switch (i % 3) {
        case 0: ops[i] = new Add(); break;
        case 1: ops[i] = new Mul(); break;
        default: ops[i] = new Xor(); break;
      }
    }
    mono = new Add();
  }

  @Benchmark
  public long polymorphicInterface() {
    long acc = 1;
    for (int r = 0; r < 4; r++) {
      for (Op op : ops) {
        acc = op.apply(acc) & 0x3fffffff;
      }
    }
    return acc;
  }

  @Benchmark
  public long monomorphicInterface() {
    long acc = 1;
    Op op = mono;
    for (int i = 0; i < 50_000; i++) {
      acc = op.apply(acc) & 0x3fffffff;
    }
    return acc;
  }
}
