import java.util.ArrayList;

/**
 * Large-heap correctness stress test. Builds a big, cross-linked object graph,
 * churns the GC (CMC concurrent compaction moves objects), and verifies every
 * object's identity afterwards. With native 64-bit references this must remain
 * correct past the old 4 GiB cap.
 *
 *   art run -Xmx<N>g -cp heapstress.dex.jar HeapStress <targetGiB>
 *
 * Each node carries a checksum derived from its index; after allocating
 * ~targetGiB of live nodes (interleaved with garbage to force compaction), we
 * walk every retained node and confirm its payload and links survived moving.
 */
public class HeapStress {
    // ~64 bytes/node of payload + header + links.
    static final class Node {
        long id;
        long check;
        Node link;     // reference field — the thing that must survive GC moves
        long[] pad;    // ballast so the heap actually fills

        Node(long id, Node link) {
            this.id = id;
            this.check = mix(id);
            this.link = link;
            this.pad = new long[4];
            this.pad[0] = mix(id ^ 0x5555555555555555L);
        }
    }

    static long mix(long x) {
        x ^= x >>> 33; x *= 0xff51afd7ed558ccdL;
        x ^= x >>> 33; x *= 0xc4ceb9fe1a85ec53L;
        x ^= x >>> 33;
        return x;
    }

    public static void main(String[] args) {
        double targetGiB = args.length > 0 ? Double.parseDouble(args[0]) : 1.0;
        long bytesPerNode = 96;                 // rough live footprint per node
        long keep = (long) (targetGiB * (1L << 30) / bytesPerNode);

        System.out.println("HeapStress: retaining " + keep + " nodes (~"
                + targetGiB + " GiB), Xmx=" + (Runtime.getRuntime().maxMemory() >> 20) + " MiB");

        // Retain a chain of `keep` nodes; allocate transient garbage between
        // links to force the collector to run and compact while we build.
        Node head = null;
        long garbage = 0;
        for (long i = 0; i < keep; i++) {
            head = new Node(i, head);
            // transient allocations (immediately dead) → GC pressure
            if ((i & 0x3F) == 0) {
                long[] junk = new long[64];
                junk[0] = i;
                garbage += junk[0];
            }
            if ((i % (keep / 16 + 1)) == 0) {
                System.out.println("  built " + i + " / " + keep
                        + "  free=" + (Runtime.getRuntime().freeMemory() >> 20) + " MiB");
            }
        }
        if (garbage == Long.MIN_VALUE) System.out.println("unreachable " + garbage);

        // Force a full compaction, then verify the whole retained graph.
        System.gc();
        System.gc();

        long n = 0;
        Node cur = head;
        long expectId = keep - 1;
        while (cur != null) {
            if (cur.id != expectId) {
                throw new AssertionError("id mismatch at walk " + n
                        + ": got " + cur.id + " want " + expectId);
            }
            if (cur.check != mix(cur.id)) {
                throw new AssertionError("checksum corruption at id " + cur.id
                        + ": got " + cur.check + " want " + mix(cur.id));
            }
            if (cur.pad == null || cur.pad.length != 4
                    || cur.pad[0] != mix(cur.id ^ 0x5555555555555555L)) {
                throw new AssertionError("payload corruption at id " + cur.id);
            }
            cur = cur.link;
            n++;
            expectId--;
        }
        if (n != keep) {
            throw new AssertionError("walked " + n + " nodes, expected " + keep);
        }
        System.out.println("HEAPSTRESS OK: verified " + n + " nodes after GC, peak heap ~"
                + (Runtime.getRuntime().totalMemory() >> 20) + " MiB");
    }
}
