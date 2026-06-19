// Regression test for the JIT On-Stack-Replacement (OSR) reference-transfer bug in the
// native-8-byte-reference fork.
//
// OSR replaces a long-running INTERPRETED loop with the optimizing-compiled version mid-loop: when
// the interpreter's loop back-edge counter gets hot, Jit::MaybeDoOnStackReplacement copies the
// interpreter ShadowFrame's live dex registers into a freshly built optimized (OSR) frame and jumps
// into compiled code (art_quick_osr_stub) at the matching loop header. In this fork an object
// reference is a native pointer-width (8-byte) value, so a live reference whose heap address is
// above 4 GiB has non-zero high bits. The OSR vreg transfer (Jit::PrepareForOsr) used to read each
// reference dex-register as a 4-byte uint32_t and write only 4 bytes into the OSR frame's 8-byte
// reference slot, truncating the high bits -> a garbage pointer that crashes the OSR'd code or the
// next GC root walk. (This is the sibling of the deopt vreg-transfer bug in
// QuickExceptionHandler::HandleOptimizingDeoptimization.) The fix reads the full 8-byte reference
// from the interpreter's References() side-array and, using the OSR stack map's reference mask to
// pick reference slots, writes all 8 bytes.
//
// This test runs ONE invocation of a long counted loop (no method re-entry, so the method is still
// being interpreted when the loop becomes hot and OSR fires INTO it). Across the loop body it keeps
// a fixed set of object references live (an array of nodes plus a running "current" reference it
// re-reads from the heap every iteration), folds their field values into a deterministic
// accumulator, and -- crucially -- DEREFERENCES those references AFTER the loop. A truncated
// reference transferred by OSR would crash (bad pointer) or fold a wrong value and diverge from the
// interpreter oracle. The loop work is a fixed, deterministic function of the inputs, independent of
// whether/where OSR fires, so JIT MUST equal -Xint, with no crash, at a >4 GiB heap.
//
// To push live references above 4 GiB we retain a large array of long-lived node objects before the
// hot loop, so the heap (and thus the addresses of the references the loop holds live) grows past
// the 4 GiB boundary on a -Xmx6g run.
public class JitOsr {
  static final class Node {
    final int val;
    Node next;
    Node(int val, Node next) { this.val = val; this.next = next; }
  }

  static volatile Object sink;

  // Allocate and retain a large set of live nodes so the heap address space grows past 4 GiB and
  // the references the hot loop holds live end up with non-zero high address bits.
  static Node[] buildLiveSet(int count, int chainLen) {
    Node[] roots = new Node[count];
    for (int i = 0; i < count; i++) {
      Node head = null;
      for (int j = 0; j < chainLen; j++) {
        head = new Node(((i * 31) + j) & 0xffff, head);
      }
      roots[i] = head;
    }
    return roots;
  }

  // The hot method: a SINGLE long-running counted loop. `roots`, `cur`, and the per-iteration
  // `probe` reference are live across the back-edge. Every iteration re-reads field values through
  // the references (so a truncated reference is dereferenced inside the loop) and walks a short
  // chain. The accumulator is a deterministic function of the inputs and the fixed iteration count.
  static long hot(Node[] roots, long iters) {
    long acc = 0;
    Node cur = roots[0];
    for (long i = 0; i < iters; i++) {
      // Re-read a reference from the heap every iteration; it stays live across the back-edge.
      Node probe = roots[(int) (i % roots.length)];
      // Dereference live references inside the loop (truncated pointer -> crash or wrong value).
      acc += probe.val;
      for (Node n = probe; n != null; n = n.next) {
        acc += n.val;
      }
      // Keep `cur` live across the loop and mutate the accumulator through it.
      acc += (cur.val & 0xff);
      // Occasionally advance `cur` along its chain so the compiler must keep it in a reference slot
      // (not fold it to a constant) and re-establish it after OSR.
      if (cur.next != null) {
        cur = cur.next;
      } else {
        cur = roots[(int) (i % roots.length)];
      }
    }
    // Use the references AFTER the loop: a reference truncated by the OSR transfer would crash here
    // or produce a value that diverges from the interpreter oracle.
    long tail = cur.val;
    for (Node r : roots) {
      tail += r.val;
    }
    return acc + tail;
  }

  static long drive() {
    // A modest retained live set. The host heap is mapped in the high (>4 GiB) virtual-address
    // region regardless of -Xmx, so even this small live set yields references with non-zero high
    // address bits on a -Xmx6g run -- enough to exercise the 8-byte OSR reference transfer. (We keep
    // the live set small so the test stays well clear of the separate large-heap GC-accounting
    // regime; the OSR transfer itself is what this test validates.)
    Node[] roots = buildLiveSet(/*count=*/ 512, /*chainLen=*/ 32);
    sink = roots;
    // One long loop in one invocation -> the method is interpreted until the loop is hot, then OSR
    // jumps into compiled code mid-loop. Fixed iteration count -> deterministic result.
    return hot(roots, 50_000_000L);
  }

  public static void main(String[] args) {
    System.out.println("JITOSR acc=" + drive());
  }
}
