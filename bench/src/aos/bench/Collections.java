package aos.bench;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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

// java.util collections -- the bread and butter of server code, and heavily reference-based
// (buckets, entries, backing arrays of references, autoboxing). Exercises hashing, the boxing
// cache, reference array loads/stores, and the write barrier.
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@State(Scope.Thread)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(0)
public class Collections {

  private String[] keys;
  private Map<String, Integer> map;
  private List<Integer> list;

  @Setup
  public void setup() {
    keys = new String[2048];
    for (int i = 0; i < keys.length; i++) {
      keys[i] = "key-" + (i * 31 + 7);
    }
    map = new HashMap<>();
    for (int i = 0; i < keys.length; i++) {
      map.put(keys[i], i);
    }
    list = new ArrayList<>();
    for (int i = 0; i < 4096; i++) {
      list.add(i);
    }
  }

  @Benchmark
  public Map<String, Integer> hashMapBuild() {
    Map<String, Integer> m = new HashMap<>();
    for (int i = 0; i < keys.length; i++) {
      m.put(keys[i], i);
    }
    return m;
  }

  @Benchmark
  public long hashMapGet() {
    long s = 0;
    for (int r = 0; r < 4; r++) {
      for (String k : keys) {
        Integer v = map.get(k);
        s += v;
      }
    }
    return s;
  }

  @Benchmark
  public long arrayListIterate(Blackhole bh) {
    long s = 0;
    for (int r = 0; r < 8; r++) {
      for (Integer v : list) {
        s += v.intValue();
      }
    }
    bh.consume(s);
    return s;
  }
}
