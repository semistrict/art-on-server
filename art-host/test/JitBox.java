// Isolates JIT reference patterns beyond basic field/array access: autoboxing
// (Integer.valueOf via the static IntegerCache.cache[] reference array), a static
// reference field, and a virtual/interface dispatch returning a reference. Run hot so
// these JIT-compile; the interpreter result is the oracle.
public class JitBox {
  interface Op { Integer apply(int x); }

  static Integer staticBox;              // static reference field
  static final Op DOUBLE = new Op() {    // virtual/interface dispatch
    public Integer apply(int x) { return x + x; }
  };

  static long boxLoop(int n) {
    long s = 0;
    for (int i = 0; i < n; i++) {
      Integer boxed = i & 0xff;          // Integer.valueOf -> IntegerCache.cache[] for small ints
      s += boxed.intValue();             // unbox
      staticBox = boxed;                 // static reference store
      s += staticBox.intValue();         // static reference load
      Integer d = DOUBLE.apply(i & 0x3f);// interface call returning a reference
      s += d.intValue();
    }
    return s;
  }

  public static void main(String[] args) {
    long acc = 0;
    for (int iter = 0; iter < 4000; iter++) {
      acc += boxLoop(1000);
    }
    System.out.println("JITBOX acc=" + acc);
  }
}
