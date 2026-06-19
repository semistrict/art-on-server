package aos.bench;

import java.util.ArrayList;
import java.util.List;
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

// java.util.stream pipelines with method-reference lambdas and autoboxing -- the exact pattern the
// optimizing-JIT 64-bit-reference work had to get right (spliterators, sink chains, Integer cache,
// invokedynamic lambdas). A realistic, allocation- and reference-heavy server idiom.
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@State(Scope.Thread)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(0)
public class Streams {

  private List<Integer> data;

  @Setup
  public void setup() {
    data = new ArrayList<>();
    for (int i = 0; i < 4096; i++) {
      data.add(i);
    }
  }

  @Benchmark
  public long mapToIntSum() {
    return data.stream().mapToInt(Integer::intValue).sum();
  }

  @Benchmark
  public long filterMapReduce() {
    return data.stream()
        .filter(x -> (x & 1) == 0)
        .mapToLong(x -> (long) x * x)
        .reduce(0L, Long::sum);
  }

  @Benchmark
  public int collectToList() {
    List<Integer> out = new ArrayList<>();
    data.stream().filter(x -> x % 3 == 0).map(x -> x + 1).forEach(out::add);
    return out.size();
  }
}
