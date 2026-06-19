import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * JIT correctness acceptance test for native pointer-width (8-byte) references.
 *
 * Every method here is called hundreds of thousands of times so the optimizing JIT
 * compiles it, then we verify the results against known-correct constants. These
 * are exactly the constructs that miscompile while the JIT still treats a reference
 * as 32-bit (it spills/loads references at the wrong width and disagrees with the
 * 8-byte heap/GC representation): stream/lambda/method-ref pipelines, iterator and
 * indexed traversal with autoboxing, object-array loads, and map-value streams.
 *
 * Correct under -Xint today; this is the target for the JIT 64-bit-reference cascade.
 */
public class JitCorrectness {
    static int streamSum(List<Integer> l) {
        return l.stream().mapToInt(Integer::intValue).sum();
    }
    static int iterSum(List<Integer> l) {
        int s = 0;
        for (Integer i : l) s += i;
        return s;
    }
    static int idxSum(List<Integer> l) {
        int s = 0;
        for (int i = 0; i < l.size(); i++) s += l.get(i);
        return s;
    }
    static long objArraySum(Long[] a) {
        long s = 0;
        for (Long x : a) s += x;           // object-array load + unbox
        return s;
    }
    static int mapValuesSum(Map<String, Integer> m) {
        return m.values().stream().mapToInt(Integer::intValue).sum();
    }
    static String concatAll(List<String> l) {
        StringBuilder b = new StringBuilder();
        for (String s : l) b.append(s);
        return b.toString();
    }

    static void check(String name, long got, long want) {
        if (got != want) throw new AssertionError(name + ": got " + got + " want " + want);
    }

    public static void main(String[] args) {
        List<Integer> ints = new ArrayList<>();
        for (int i = 1; i <= 100; i++) ints.add(i);          // sum 5050
        List<String> strs = Arrays.asList("a", "b", "c", "d", "e");
        Long[] longs = new Long[64];
        for (int i = 0; i < 64; i++) longs[i] = (long) i;     // sum 2016
        Map<String, Integer> m = new HashMap<>();
        for (int i = 0; i < 200; i++) m.put("k" + i, i);      // sum 19900

        int rounds = args.length > 0 ? Integer.parseInt(args[0]) : 400000;
        int a = 0, b = 0, c = 0, e = 0;
        long d = 0;
        String f = null;
        for (int r = 0; r < rounds; r++) {
            a = streamSum(ints);
            b = iterSum(ints);
            c = idxSum(ints);
            d = objArraySum(longs);
            e = mapValuesSum(m);
            f = concatAll(strs);
        }
        check("streamSum", a, 5050);
        check("iterSum", b, 5050);
        check("idxSum", c, 5050);
        check("objArraySum", d, 2016);
        check("mapValuesSum", e, 19900);
        if (!"abcde".equals(f)) throw new AssertionError("concatAll: " + f);
        System.out.println("JITCORRECTNESS OK: stream=" + a + " iter=" + b + " idx=" + c
                + " objarr=" + d + " map=" + e + " concat=" + f);
    }
}
