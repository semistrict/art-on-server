// Regression test for a JIT GC-stack-map / outgoing-argument frame-layout bug in the
// native-8-byte-reference fork.
//
// In this fork an object reference is a 64-bit value, so a reference argument PASSED ON THE STACK
// occupies a DoubleStackSlot (two 4-byte machine slots), exactly like a long/double -- the arm64
// calling convention advances its outgoing stack cursor by 2 for each reference. The compiler,
// however, sized the outgoing-argument frame region from the dex `outs_size`
// (HInvoke::GetNumberOfOutVRegs(), which counts a reference as a single vreg). Whenever a call
// passed references on the stack, the marshalled 8-byte references overflowed the (under-sized)
// outgoing-argument region and clobbered the adjacent reference SPILL slots. The GC stack map still
// marked those spill slots as live references, so a concurrent GC tried to mark the clobbered value
// (a primitive int) and aborted ("invalid reference" / BADSTACK_ROOT).
//
// This reproduces it: a hot loop that, every iteration, allocates (so a GC fires at the loop
// back-edge safepoint) and CALLS a method taking eleven reference arguments -- more than the arm64
// GP argument registers, so several references are marshalled onto the outgoing-argument stack
// area. Reference values that the register allocator spilled into frame slots are live across that
// call's safepoint; the outgoing-argument overflow corrupts them. The interpreter is the oracle:
// the JIT MUST equal -Xint, with no GC crash.
public class JitGcRoots {
  static final class Box {
    final int v;
    Box(int v) { this.v = v; }
  }

  // Eleven reference parameters: more than the GP arg registers, so the trailing references are
  // marshalled onto the outgoing-argument stack area. Returns a deterministic mix of them.
  static int mix(Box a, Box b, Box c, Box d, Box e, Box f,
                 Box g, Box h, Box k, Box l, Box m, int seed) {
    return ((a.v + b.v + c.v + d.v + e.v + f.v + g.v + h.v + k.v + l.v + m.v) & 1) + (seed & 1);
  }

  static long churn(Box a, Box b, Box c, Box d, Box e, Box f,
                    Box g, Box h, Box k, Box l, Box m,
                    int seed, int n) {
    long acc = seed;
    for (int i = 0; i < n; i++) {
      // Allocate every iteration: forces frequent GC and a safepoint at the call/back-edge.
      int[] tmp = new int[(i & 3) + 1];
      tmp[i & (tmp.length - 1)] = i;
      // Call with eleven reference args -> several are passed on the outgoing-argument stack area.
      // The references a..m and the spilled temporaries are live across this call's GC safepoint.
      acc += mix(a, b, c, d, e, f, g, h, k, l, m, seed + i) + tmp[i & (tmp.length - 1)];
    }
    return acc;
  }

  static long run() {
    Box a = new Box(1), b = new Box(2), c = new Box(3), d = new Box(4);
    Box e = new Box(5), f = new Box(6), g = new Box(7), h = new Box(8);
    Box k = new Box(9), l = new Box(10), m = new Box(11);
    long acc = 0;
    for (int iter = 0; iter < 400000; iter++) {
      acc += (churn(a, b, c, d, e, f, g, h, k, l, m, iter & 1, 48) & 0xff);
    }
    return acc;
  }

  public static void main(String[] args) {
    System.out.println("JITGCROOTS acc=" + run());
  }
}
