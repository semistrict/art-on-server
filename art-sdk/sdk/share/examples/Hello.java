public class Hello {
    public static void main(String[] args) {
        String who = args.length > 0 ? args[0] : "world";
        System.out.println("Hello, " + who + ", from ART on "
                + System.getProperty("os.arch"));
    }
}
