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

// Reference-free scalar compute: a baseline for raw JIT codegen quality (loops, induction
// variables, int/long/double ALU, array element math). No object references, so the 8-byte vs
// 4-byte reference representation does not enter -- this isolates the optimizing compiler.
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@State(Scope.Thread)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(0)
public class Arithmetic {

  private final int[] ia = new int[4096];
  private final double[] da = new double[4096];

  {
    for (int i = 0; i < ia.length; i++) {
      ia[i] = i * 2654435761L >>> 1 == 0 ? 1 : (i ^ (i << 3)) + 1;
      da[i] = (i % 97) * 0.5 + 1.0;
    }
  }

  @Benchmark
  public long longArithmetic() {
    long acc = 1;
    for (int i = 1; i < 20_000; i++) {
      acc = acc * 1103515245L + 12345L;
      acc ^= acc >>> 17;
      acc += (long) i * i;
    }
    return acc;
  }

  @Benchmark
  public double doubleArithmetic() {
    double acc = 1.0;
    for (int i = 0; i < da.length; i++) {
      acc = acc * 1.0000001 + Math.sqrt(da[i]) - da[i] * 0.5;
    }
    return acc;
  }

  @Benchmark
  public long intArrayReduce() {
    long s = 0;
    for (int r = 0; r < 5; r++) {
      for (int i = 0; i < ia.length; i++) {
        s += (long) ia[i] * (ia[i] & 0xff) - (ia[i] >> 3);
      }
    }
    return s;
  }
}
