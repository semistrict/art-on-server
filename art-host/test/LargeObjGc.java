import java.util.ArrayList;

/**
 * Exercises the large-object space under the concurrent mark-compact GC.
 *
 * Each array is well above the large-object threshold, so it lands in the LOS
 * rather than the main heap. We retain a bounded working set and churn the rest
 * to force repeated GC cycles, then verify every retained array's checksum.
 *
 * This pins down the large-object mark-compact path (MarkCompact::Mark*
 * LargeObjects), which indexes large objects through a bitmap sized for the
 * heap's address range. The LOS must therefore sit on the same side of the
 * 4 GiB line as the main heap (see LargeObjectMapSpace::Create) -- otherwise a
 * large object is indexed out of the bitmap and the collector crashes. Run in
 * the default (JIT) mode at <=4 GiB to also confirm references stay 32-bit.
 */
public class LargeObjGc {
    static final int ARRAY_BYTES = 8 * 1024 * 1024;  // 8 MiB -> large object

    static byte fill(int id, int idx) {
        return (byte) ((id * 31 + idx * 7) & 0xff);
    }

    public static void main(String[] args) {
        int totalMiB = args.length > 0 ? Integer.parseInt(args[0]) : 512;
        int keep = args.length > 1 ? Integer.parseInt(args[1]) : 16;
        int rounds = (int) ((long) totalMiB * 1024 * 1024 / ARRAY_BYTES);

        ArrayList<byte[]> live = new ArrayList<>();
        int[] liveIds = new int[keep];
        for (int r = 0; r < rounds; r++) {
            byte[] b = new byte[ARRAY_BYTES];
            // Stamp first/last/middle so pages commit and the contents are verifiable.
            b[0] = fill(r, 0);
            b[ARRAY_BYTES / 2] = fill(r, ARRAY_BYTES / 2);
            b[ARRAY_BYTES - 1] = fill(r, ARRAY_BYTES - 1);
            if (live.size() < keep) {
                liveIds[live.size()] = r;
                live.add(b);
            } else {
                // Replace a slot: the previous large object becomes garbage -> GC pressure.
                int slot = r % keep;
                liveIds[slot] = r;
                live.set(slot, b);
            }
            if ((r & 0x7) == 0x7) {
                System.gc();
            }
        }
        // Force a full compaction, then verify the retained large objects survived intact.
        System.gc();
        System.gc();

        for (int s = 0; s < live.size(); s++) {
            byte[] b = live.get(s);
            int id = liveIds[s];
            if (b.length != ARRAY_BYTES
                    || b[0] != fill(id, 0)
                    || b[ARRAY_BYTES / 2] != fill(id, ARRAY_BYTES / 2)
                    || b[ARRAY_BYTES - 1] != fill(id, ARRAY_BYTES - 1)) {
                throw new AssertionError("large object corruption at slot " + s + " id " + id);
            }
        }
        System.out.println("LARGEOBJ OK: " + rounds + " large arrays allocated ("
                + totalMiB + " MiB churned), " + live.size()
                + " retained and verified after GC, Xmx="
                + (Runtime.getRuntime().maxMemory() >> 20) + " MiB");
    }
}
