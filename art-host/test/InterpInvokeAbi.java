import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

/**
 * Regression test for the interpreter invoke-ABI under native pointer-width (8-byte)
 * references. Three things broke when a receiver/reference was read at the stock
 * 4-byte width on the interpreter's invoke path:
 *
 *  1. Class.newInstance() (the deprecated reflective allocator, native Class_newInstance)
 *     truncated the receiver to 32 bits -> garbage `this` -> crash. java.nio's default
 *     FileSystemProvider is created exactly this way, so file I/O depended on it.
 *  2. QuickArgumentVisitor advanced the stack-arg cursor by one 4-byte slot for the
 *     8-byte receiver/reference, so every argument of a non-static method/constructor
 *     that spilled past the argument registers was read at the wrong offset -> scrambled
 *     longs/ints/refs.
 *
 * Each check below has a known-correct expected value; any truncation/misalignment
 * yields a wrong value or a crash. Run on the interpreter (-Xint) -- that is the path
 * these fixes are on.
 */
public class InterpInvokeAbi {

    public static class Base {
        final String id;
        Base() {
            // System.getProperty exercises a static invoke + move-result before the
            // first virtual call on `this` (the shape that crashed in nio provider init).
            String dir = System.getProperty("user.dir");
            id = getClass().getName() + (dir != null ? "" : "?");
        }
    }
    public static class Sub extends Base { public Sub() { super(); } }

    // Non-static, args spill past the ~7 argument registers: receiver + 12 mixed args.
    public long sum(long a, int b, long c, int d, long e, int f,
                    long g, int h, long i, int j, long k, int l) {
        return a + b + c + d + e + f + g + h + i + j + k + l;
    }
    public final long base;
    public InterpInvokeAbi() { base = 0; }
    // Non-static constructor with stack-spilling args.
    public InterpInvokeAbi(long a, int b, long c, int d, long e, int f, long g, int h) {
        base = a + b + c + d + e + f + g + h;
    }

    static void check(String what, Object got, Object want) {
        if (!got.equals(want)) {
            throw new AssertionError(what + ": got " + got + " want " + want);
        }
    }

    public static void main(String[] args) throws Exception {
        // (1) deprecated Class.newInstance() -> native Class_newInstance receiver.
        Object o = Class.forName("InterpInvokeAbi$Sub").newInstance();
        check("Class.newInstance", ((Base) o).id, "InterpInvokeAbi$Sub");

        // (2) java.nio default provider (instantiated via Class.newInstance internally).
        String fsClass = java.nio.file.FileSystems.getDefault().getClass().getName();
        check("FileSystems.getDefault non-null", fsClass.isEmpty(), false);

        // (3) non-static many-arg method via reflection (receiver + stack-spilled args).
        Class<?>[] sig = {long.class, int.class, long.class, int.class, long.class, int.class,
                          long.class, int.class, long.class, int.class, long.class, int.class};
        Method m = InterpInvokeAbi.class.getMethod("sum", sig);
        check("non-static many-arg method",
              m.invoke(new InterpInvokeAbi(), 1L, 2, 3L, 4, 5L, 6, 7L, 8, 9L, 10, 11L, 12),
              78L);

        // (4) non-static many-arg constructor via reflection.
        Class<?>[] csig = {long.class, int.class, long.class, int.class,
                           long.class, int.class, long.class, int.class};
        Constructor<InterpInvokeAbi> c = InterpInvokeAbi.class.getConstructor(csig);
        check("non-static many-arg ctor", c.newInstance(1L, 2, 3L, 4, 5L, 6, 7L, 8).base, 36L);

        System.out.println("INTERP-INVOKE-ABI OK: fs=" + fsClass);
    }
}
