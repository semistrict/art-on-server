import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import java.util.List;

/**
 * Uses a real Maven dependency (Gson) with ZERO pre-dexing. Build and run:
 *
 *   curl -O https://repo1.maven.org/maven2/com/google/code/gson/gson/2.11.0/gson-2.11.0.jar
 *   art compile -cp gson-2.11.0.jar -d inventory.dex.jar InventoryReport.java
 *   art run     -cp inventory.dex.jar:gson-2.11.0.jar InventoryReport
 *
 * `art run` transparently dexes gson-2.11.0.jar (a normal .class jar) and
 * caches the result, so the JVM/Maven ecosystem works unchanged.
 */
public class InventoryReport {
    static class Item {
        String sku;
        int qty;
        double price;
        Item(String sku, int qty, double price) {
            this.sku = sku;
            this.qty = qty;
            this.price = price;
        }
    }

    public static void main(String[] args) {
        Gson gson = new GsonBuilder().setPrettyPrinting().create();
        List<Item> items = List.of(
                new Item("A-100", 7, 12.50),
                new Item("B-200", 3, 99.99));

        String json = gson.toJson(items);
        System.out.println(json);

        Item[] back = gson.fromJson(json, Item[].class);
        double total = 0;
        for (Item it : back) {
            total += it.qty * it.price;
        }
        System.out.printf("parsed %d items, inventory value = %.2f%n", back.length, total);
    }
}
