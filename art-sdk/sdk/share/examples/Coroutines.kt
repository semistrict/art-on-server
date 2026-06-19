import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking

/**
 * Server-side Kotlin on ART: data classes, the standard library, and
 * kotlinx.coroutines — all consumed as ordinary Maven .class jars that the
 * SDK dexes transparently.
 *
 *   art kotlinc -d app.dex.jar Coroutines.kt
 *   art run -cp app.dex.jar:<kotlin-stdlib>:<kotlinx-coroutines-core> CoroutinesKt
 */
data class Quote(val symbol: String, val price: Double)

suspend fun fetchQuote(symbol: String): Quote {
    delay(20)                     // pretend this is network I/O
    return Quote(symbol, symbol.hashCode().toDouble() % 1000 / 10.0)
}

fun main() = runBlocking {
    val symbols = listOf("ART", "JVM", "GC", "AOT", "DEX")
    val quotes = symbols.map { sym -> async { fetchQuote(sym) } }.awaitAll()
    quotes.sortedByDescending { it.price }.forEach { q ->
        println("%-4s %.1f".format(q.symbol, q.price))
    }
    println("fetched ${quotes.size} quotes concurrently on ART")
}
