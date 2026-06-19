// Minimal reproducer for the remaining JIT gap: a java.util stream pipeline driven by a
// method-reference lambda (Integer::intValue). The interpreter result is the oracle; the JIT
// must match. Isolates the stream/spliterator/lambda path from the rest of JitCorrectness.
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class JitStream {
  static long listSum(List<Integer> list) {
    return list.stream().mapToInt(Integer::intValue).sum();
  }

  static long mapValuesSum(Map<Integer, Integer> map) {
    return map.values().stream().mapToInt(Integer::intValue).sum();
  }

  public static void main(String[] args) {
    List<Integer> list = new ArrayList<>();
    Map<Integer, Integer> map = new HashMap<>();
    for (int i = 0; i < 1000; i++) {
      list.add(i);
      map.put(i, i * 2);
    }
    long acc = 0;
    for (int iter = 0; iter < 5000; iter++) {
      acc += listSum(list);
      acc += mapValuesSum(map);
    }
    System.out.println("JITSTREAM acc=" + acc);
  }
}
