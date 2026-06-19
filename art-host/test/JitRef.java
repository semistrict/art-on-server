// Minimal deterministic JIT reference-codegen test (no streams/boxing/StringBuilder).
// Exercises the core 64-bit-reference paths in the optimizing compiler: reference field
// loads, reference array loads, null checks, and reference parameters/returns -- in hot
// methods so they are JIT-compiled. The interpreter result is the oracle; the JIT must match.
public class JitRef {
  static final class Node {
    Node next;
    int val;
    Node(int v) { val = v; }
  }

  // Reference field load + null check in a hot loop.
  static long walk(Node head) {
    long s = 0;
    for (Node n = head; n != null; n = n.next) {
      s += n.val;
    }
    return s;
  }

  // Reference array load + reference field load.
  static long arrSum(Node[] a) {
    long s = 0;
    for (int i = 0; i < a.length; i++) {
      Node n = a[i];
      if (n != null) {
        s += n.val;
      }
    }
    return s;
  }

  // Reference parameter passed through, reference return value.
  static Node pick(Node a, Node b, boolean which) {
    return which ? a : b;
  }

  public static void main(String[] args) {
    Node head = null;
    for (int i = 0; i < 1000; i++) {
      Node n = new Node(i);
      n.next = head;
      head = n;
    }
    Node[] a = new Node[256];
    for (int i = 0; i < a.length; i++) {
      a[i] = ((i & 7) == 0) ? null : new Node(i);
    }

    // Warm up so walk/arrSum/pick become hot and get JIT-compiled.
    long acc = 0;
    for (int iter = 0; iter < 300000; iter++) {
      acc += walk(head);
      acc += arrSum(a);
      Node p = pick(head, a[1], (iter & 1) == 0);
      acc += (p == null) ? 0 : p.val;
    }
    // walk(head) = sum 0..999 = 499500; arrSum(a) = sum of vals where i&7 != 0.
    System.out.println("JITREF acc=" + acc);
  }
}
