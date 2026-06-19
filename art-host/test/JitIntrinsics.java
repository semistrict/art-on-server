// Exercises the arm64 optimizing-JIT INTRINSIC + stub reference paths that are only correct when a
// reference is treated as a native 8-byte value. On a >4 GiB heap (references map high) any path
// that still handles a reference at 4-byte width truncates; the interpreter (-Xint) is the oracle.
//
// Covers: Object[] System.arraycopy, Thread.currentThread(), java.lang.ref.WeakReference
// get()/refersTo(), AtomicReference compareAndSet/compareAndExchange/getAndSet, String.equals,
// checked Object[] stores (aput-object slow path), and a many-argument call that forces a
// reference onto the outgoing stack-arg area. Each contributes to a single checksum so any
// truncation changes the result (or crashes), and JIT must equal -Xint.
import java.lang.ref.WeakReference;
import java.util.concurrent.atomic.AtomicReference;

public class JitIntrinsics {

  // --- G1: Object[] System.arraycopy (per-element reference copy) ---
  static long arrayCopySum(Integer[] src) {
    Integer[] dst = new Integer[src.length];
    System.arraycopy(src, 0, dst, 0, src.length);
    long s = 0;
    for (Integer v : dst) s += v.intValue();
    return s;
  }

  // --- G2: Thread.currentThread() identity (the peer reference must not truncate) ---
  static long currentThreadId(Thread expected) {
    Thread t = Thread.currentThread();
    // Identity + a field read through the returned reference.
    return (t == expected ? 1 : 0) + (long) t.getName().length();
  }

  // --- G3: java.lang.ref.Reference get()/refersTo() ---
  static long weakRef(Object referent, Object other) {
    WeakReference<Object> w = new WeakReference<>(referent);
    long s = 0;
    if (w.get() == referent) s += 1;     // get() must return the exact reference
    if (w.refersTo(referent)) s += 2;    // refersTo(same) must be true
    if (!w.refersTo(other)) s += 4;      // refersTo(different) must be false
    return s;
  }

  // --- G4: AtomicReference CAS / exchange (reference compare-and-set) ---
  static long atomicRef(Object a, Object b) {
    AtomicReference<Object> ref = new AtomicReference<>(a);
    long s = 0;
    if (ref.compareAndSet(a, b)) s += 1;       // expected==current -> swap
    if (ref.get() == b) s += 2;
    if (!ref.compareAndSet(a, a)) s += 4;      // expected!=current -> no swap
    Object prev = ref.getAndSet(a);
    if (prev == b) s += 8;
    if (ref.get() == a) s += 16;
    return s;
  }

  // --- G5: String.equals (reference null-check + identity + class compare) ---
  static long stringEquals(String x, String y, String z) {
    long s = 0;
    if (x.equals(x)) s += 1;       // same reference
    if (x.equals(y)) s += 2;       // equal content, different reference
    if (!x.equals(z)) s += 4;      // different content
    if (!x.equals(null)) s += 8;   // null argument
    if (!x.equals(Integer.valueOf(3))) s += 16;  // non-String argument (class compare)
    return s;
  }

  // --- G8: checked Object[] store (aput-object that needs the runtime assignability check) ---
  static long checkedArrayStore(int n) {
    Number[] arr = new Integer[n];          // array component type = Integer
    long s = 0;
    for (int i = 0; i < n; i++) {
      Object v = Integer.valueOf(i & 0x3f); // typed as Object -> store needs a runtime check
      arr[i] = (Number) v;                  // aput-object slow path (kQuickAputObject)
    }
    for (int i = 0; i < n; i++) s += arr[i].intValue();
    return s;
  }

  // --- G6: many-argument call forcing a reference into the outgoing stack-arg area ---
  static long manyArgs(int a, int b, int c, int d, int e, int f, int g, int h,
                       Object ref, int i, Object ref2, int j) {
    // `ref` / `ref2` land past the GP argument registers -> passed on the stack.
    return (long) ref.hashCode() + ref2.hashCode() + a + b + c + d + e + f + g + h + i + j;
  }

  static long run() {
    long acc = 0;
    Integer[] src = new Integer[64];
    for (int i = 0; i < src.length; i++) src[i] = i;
    Thread self = Thread.currentThread();
    String s1 = new String("hello-world");
    String s2 = new String("hello-world");
    String s3 = "hello-there";
    Object oa = new Object();
    Object ob = new Object();
    Object ref1 = "stack-ref-1";
    Object ref2 = "stack-ref-2";

    for (int iter = 0; iter < 20000; iter++) {
      acc += arrayCopySum(src);
      acc += currentThreadId(self);
      acc += weakRef(oa, ob);
      acc += atomicRef(oa, ob);
      acc += stringEquals(s1, s2, s3);
      acc += checkedArrayStore(64);
      acc += manyArgs(1, 2, 3, 4, 5, 6, 7, 8, ref1, 9, ref2, 10);
    }
    return acc;
  }

  public static void main(String[] args) {
    long acc = run();
    System.out.println("JITINTRINSICS acc=" + acc);
  }
}
