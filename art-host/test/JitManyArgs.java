// G6 check: a method with more reference arguments than there are GP argument registers, so
// several references are passed in the OUTGOING STACK-ARG area. Exercised three ways at a >4 GiB
// heap (references map high): a direct (JIT-compiled) call, and a java.lang.reflect call that goes
// through ArtMethod::Invoke / the invoke stub / QuickArgumentVisitor (the runtime arg-marshaling
// path). All must agree with the interpreter oracle; a 4-byte stack-slot or a 1-vs-2-slot layout
// mismatch would truncate a high reference (crash in hashCode()) or scramble the arguments.
import java.lang.reflect.Method;

public class JitManyArgs {
  // 6 ints fill most GP arg registers, then six references must spill to the stack.
  static long pack(int a, int b, int c,
                   Object r1, Object r2, Object r3, Object r4, Object r5, Object r6,
                   int d, int e, int f) {
    // hashCode() is a virtual call through each reference: a truncated reference would fault.
    long h = (long) r1.hashCode() * 1
           + (long) r2.hashCode() * 2
           + (long) r3.hashCode() * 3
           + (long) r4.hashCode() * 4
           + (long) r5.hashCode() * 5
           + (long) r6.hashCode() * 6;
    return h + a + b * 10L + c * 100L + d * 1000L + e * 10000L + f * 100000L;
  }

  static long run() throws Exception {
    Object[] refs = new Object[6];
    for (int i = 0; i < 6; i++) refs[i] = ("ref-" + i).intern();
    Method m = JitManyArgs.class.getDeclaredMethod(
        "pack", int.class, int.class, int.class,
        Object.class, Object.class, Object.class, Object.class, Object.class, Object.class,
        int.class, int.class, int.class);
    long acc = 0;
    for (int iter = 0; iter < 20000; iter++) {
      // Direct call (JIT-compiled): references r1..r6 spill to the outgoing stack-arg area.
      acc += pack(1, 2, 3, refs[0], refs[1], refs[2], refs[3], refs[4], refs[5], 4, 5, 6);
      // Reflective call: args marshalled by ArtMethod::Invoke + invoke stub + QuickArgumentVisitor.
      acc += (Long) m.invoke(null, 1, 2, 3,
          refs[0], refs[1], refs[2], refs[3], refs[4], refs[5], 4, 5, 6);
    }
    return acc;
  }

  public static void main(String[] args) throws Exception {
    System.out.println("JITMANYARGS acc=" + run());
  }
}
