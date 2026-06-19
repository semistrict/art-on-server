// Minimal deterministic reproducer for the JIT deoptimization reference-transfer bug in the
// native-8-byte-reference fork.
//
// Deoptimization copies an optimized (JIT) frame's dex-register values -- INCLUDING object
// references -- into an interpreter ShadowFrame, using the precise CodeInfo dex-register map. In
// this fork a reference is a native pointer-width (8-byte) value, so a live reference whose heap
// address is above 4 GiB has non-zero high bits. The deopt frame builder
// (QuickExceptionHandler::HandleOptimizingDeoptimization) read each reference dex-register as a
// 4-byte uint32_t (truncating the high bits) and fed that bad pointer to SetVRegReference,
// crashing in DeoptimizeSingleFrame (or, downstream, in the GC root walk). This is the sibling of
// the OSR vreg transfer, which was disabled rather than fixed for the same reason.
//
// We force a single-frame deopt FROM COMPILED CODE deterministically and cheaply (no OOM, no GC, no
// thread race) using a MONOMORPHIC INLINE CACHE. During warm-up, hot() only ever sees Circle as the
// receiver of s.area(); the optimizing compiler compiles that call site with a monomorphic inline
// cache for Circle, inlines Circle.area(), and guards it with an HDeoptimize that fires if a
// different receiver type ever appears. After hot() is JIT-compiled, we call it ONCE with a Square
// receiver: the inline-cache type guard fails and the optimized frame deoptimizes single-frame --
// exactly the crashing path (artDeoptimizeFromCompiledCode) -- while object references (`s`,
// `keep`, `head`) are live and must be transferred into the interpreter frame at full 8-byte width.
//
// hot() runs a FIXED iteration count of identical work, so its result is deterministic and
// invariant to whether/where the deopt fires (the interpreter oracle computes the same value with
// no deopt). A truncated reference would crash (bad pointer) or fold a wrong field value and
// diverge. JIT MUST equal -Xint, no crash, at <=4 GiB and >4 GiB.
public class JitDeopt {
  static abstract class Shape {
    final int tag;
    final int v;
    Shape(int tag, int v) { this.tag = tag; this.v = v; }
    abstract int area();
  }

  static final class Circle extends Shape {
    Circle(int r) { super(1, r); }
    int area() { return v * v * 3; }
  }

  static final class Square extends Shape {
    Square(int s) { super(2, s); }
    int area() { return v * v; }
  }

  static final class Node {
    final Node next;
    final int val;
    Node(int val, Node next) { this.val = val; this.next = next; }
  }

  static volatile Object sink;

  // Hot, JIT-compiled method. The s.area() call site becomes a monomorphic (Circle-only) inline
  // cache guarded by an HDeoptimize. Holds `s`/`keep`/`head` live across that guard. A FIXED
  // iteration count keeps the result deterministic. When a non-Circle receiver appears, the guard
  // fails and this optimized frame deoptimizes single-frame; the references must survive at full
  // 8-byte width.
  static long hot(Shape s, Node keep, Node head, int iters) {
    long acc = 0;
    for (int i = 0; i < iters; i++) {
      acc += s.area();                              // monomorphic inline cache; HDeoptimize guard.
      for (Node n = head; n != null; n = n.next) acc += n.val;
      acc += (keep.val & 0xff) + (s.tag << 8);      // live references folded every iteration.
    }
    return acc + keep.val + head.val + s.tag;       // references must be intact after the deopt.
  }

  static Node makeChain(int n) {
    Node head = null;
    for (int i = 0; i < n; i++) head = new Node(i + 1, head);
    return head;
  }

  static long drive() throws Exception {
    final Node head = makeChain(16);
    final Node keep = new Node(0x5eed, head);
    final Shape circle = new Circle(7);
    final Shape square = new Square(5);

    long acc = 0;
    // Warm up hot() with ONLY Circle so the s.area() call site is compiled as a monomorphic inline
    // cache for Circle, guarded by an HDeoptimize (Baseline -> Optimized).
    for (int w = 0; w < 300000; w++) {
      acc += hot(circle, keep, head, 8);
    }
    // The optimizing compile runs asynchronously on a JIT thread; give it time to install the
    // optimized, inline-cache-guarded hot() before we feed it the off-type receiver.
    Thread.sleep(200);

    // Feed a Square receiver: the monomorphic inline-cache guard fails -> single-frame deopt of the
    // optimized hot() frame, with `square`/`keep`/`head` live. Fixed iters -> deterministic result.
    acc += hot(square, keep, head, 200000);

    // And a few more mixed calls (now polymorphic) -- still deterministic.
    acc += hot(circle, keep, head, 8);
    acc += hot(square, keep, head, 8);
    acc += keep.val + circle.area() + square.area() + head.val;
    return acc;
  }

  public static void main(String[] args) throws Exception {
    System.out.println("JITDEOPT acc=" + drive());
  }
}
