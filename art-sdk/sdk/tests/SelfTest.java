import java.security.MessageDigest;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.Locale;

/**
 * SDK acceptance test. Compiled with `art compile` and run with `art run` by
 * the selftest harness — a green run proves the whole toolchain
 * (ECJ + d8 + runtime) plus ICU locale data, tzdata, and crypto all work in
 * the unpacked SDK with no external dependencies.
 */
public class SelfTest {
    public static void main(String[] args) throws Exception {
        // ICU locale data: Turkish dotted-capital I.
        check("icu-locale", "İSTANBUL",
                "istanbul".toUpperCase(Locale.forLanguageTag("tr-TR")));

        // Named zone resolution comes from the bundled tzdata module.
        ZonedDateTime utc = ZonedDateTime.now(ZoneId.of("UTC"));
        ZonedDateTime ny = utc.withZoneSameInstant(ZoneId.of("America/New_York"));
        int offset = ny.getOffset().getTotalSeconds() / 3600;
        if (offset != -4 && offset != -5) {
            throw new AssertionError("tzdata broken: NY offset " + offset);
        }
        System.out.println("ok tzdata = America/New_York offset " + offset);

        // Crypto via the conscrypt/boringssl provider.
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        byte[] digest = md.digest("art".getBytes("UTF-8"));
        StringBuilder hex = new StringBuilder();
        for (byte b : digest) {
            hex.append(String.format("%02x", b));
        }
        check("sha256",
                "d3cec99112255db9bf4963f7798562b6a36f1bd0b2016918629e007d474deb70",
                hex.toString());

        System.out.println("SELFTEST OK on " + System.getProperty("os.arch"));
    }

    private static void check(String name, String expected, String actual) {
        if (!expected.equals(actual)) {
            throw new AssertionError(name + ": expected " + expected + " got " + actual);
        }
        System.out.println("ok " + name + " = " + actual);
    }
}
