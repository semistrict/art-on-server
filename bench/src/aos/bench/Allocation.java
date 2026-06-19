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

// Allocation + GC pressure. Exercises the TLAB fast path, object header writes, and the collector
// (ART CMC vs HotSpot G1). Reference-heavy: nodes hold references, so the 8-byte reference
// representation (vs HotSpot compressed oops) shows up as larger objects / more memory traffic.
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@State(Scope.Thread)
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(0)
public class Allocation {

  static final class Node {
    int value;
    Node next;
    Object payload;

    Node(int v, Node n) {
      value = v;
      next = n;
      payload = n == null ? this : n.payload;
    }
  }

  @Benchmark
  public Node buildList() {
    // Short-lived garbage: 10k small reference-holding objects, immediately collectable.
    Node head = null;
    for (int i = 0; i < 10_000; i++) {
      head = new Node(i, head);
    }
    return head;
  }

  @Benchmark
  public long walkAndDrop() {
    // Build then walk a chain; the walk is pure reference-field chasing (8-byte loads).
    Node head = null;
    for (int i = 0; i < 8_000; i++) {
      head = new Node(i, head);
    }
    long s = 0;
    for (Node n = head; n != null; n = n.next) {
      s += n.value;
    }
    return s;
  }

  @Benchmark
  public void objectArrays(Blackhole bh) {
    // Object[] churn: allocate, fill with references, read back.
    for (int r = 0; r < 64; r++) {
      Object[] a = new Object[256];
      for (int i = 0; i < a.length; i++) {
        a[i] = (i & 1) == 0 ? Integer.valueOf(i) : (Object) a;
      }
      long s = 0;
      for (Object o : a) {
        s += o.hashCode() & 0xff;
      }
      bh.consume(s);
    }
  }
}
