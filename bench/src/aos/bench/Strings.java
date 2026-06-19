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
import org.openjdk.jmh.infra.Blackhole;

// String-heavy work: builder concatenation, hashing, equals. Exercises char[] backing arrays, the
// String.equals / arraycopy / indexOf intrinsics, and a lot of short-lived allocation.
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@State(Scope.Thread)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(0)
public class Strings {

  private String[] words;

  @Setup
  public void setup() {
    words = new String[512];
    for (int i = 0; i < words.length; i++) {
      words[i] = "token_" + (i * 1315423911) + "_" + (i % 7);
    }
  }

  @Benchmark
  public String builderConcat() {
    StringBuilder sb = new StringBuilder(8192);
    for (int i = 0; i < words.length; i++) {
      sb.append(words[i]).append('=').append(i).append(';');
    }
    return sb.toString();
  }

  @Benchmark
  public long hashAndEquals(Blackhole bh) {
    long s = 0;
    for (int r = 0; r < 8; r++) {
      for (int i = 0; i < words.length; i++) {
        String w = words[i];
        s += w.hashCode();
        // equals against a freshly built equal string -> char-by-char compare (not identity).
        if (w.equals(new StringBuilder(w).toString())) {
          s += w.length();
        }
      }
    }
    bh.consume(s);
    return s;
  }
}
