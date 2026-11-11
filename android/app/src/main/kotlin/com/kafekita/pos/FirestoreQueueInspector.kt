package com.kafekita.pos

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import java.io.File
import java.security.MessageDigest

/** Read-only schema inspection. Unknown/mixed queues are never cleared. */
class FirestoreQueueInspector(private val context: Context) {
    private fun digest(file: File): ByteArray {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest()
    }
    private val accountPaths = setOf(
        "users/u_barista_default", "users/u_admin_default", "users/u_owner_default")

    private fun database(projectId: String): File? {
        require(projectId.matches(Regex("[a-z0-9-]{1,100}")))
        val matches = context.databaseList().filter {
            it.startsWith("firestore.") && it.contains(".$projectId.") &&
                !it.endsWith("-journal") && !it.endsWith("-wal") && !it.endsWith("-shm")
        }
        check(matches.size <= 1) { "Multiple Firestore databases require review" }
        return matches.firstOrNull()?.let { context.getDatabasePath(it) }
    }

    fun inspect(projectId: String): Map<String, Any> {
        val file = database(projectId) ?: return mapOf(
            "inspected" to true, "pendingBatches" to 0, "accountsOnly" to false)
        SQLiteDatabase.openDatabase(file.path, null,
            SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).use { db ->
            val total = db.rawQuery("SELECT COUNT(*) FROM mutations", null).use {
                check(it.moveToFirst()); it.getLong(0)
            }
            var references = 0L
            var safe = true
            val documents = mutableMapOf<String, Long>()
            db.rawQuery("SELECT uid, path, COUNT(*) FROM document_mutations GROUP BY uid, path", null).use { rows ->
                while (rows.moveToNext()) {
                    val path = rows.getString(1).replace("\u0001\u0001", "/").trim('/')
                    val count = rows.getLong(2)
                    references += count
                    if (rows.getString(0).isNotEmpty() || path !in accountPaths) safe = false
                    documents[path] = (documents[path] ?: 0) + count
                }
            }
            val distinct = db.rawQuery("SELECT COUNT(DISTINCT batch_id) FROM document_mutations", null).use {
                check(it.moveToFirst()); it.getLong(0)
            }
            val sales = mutableListOf<String>()
            db.rawQuery("SELECT path FROM remote_documents WHERE path LIKE 'transactions%'", null).use { rows ->
                while (rows.moveToNext()) {
                    val path = rows.getString(0).replace("\u0001\u0001", "/").trim('/')
                    if (path.startsWith("transactions/")) sales += path.removePrefix("transactions/")
                }
            }
            safe = safe && references == total && distinct == total && total > 0
            return mapOf("inspected" to true, "pendingBatches" to total,
                "accountsOnly" to safe, "documents" to documents, "cachedTransactionIds" to sales)
        }
    }

    fun backup(projectId: String, expected: Long): String {
        val before = inspect(projectId)
        check(before["accountsOnly"] == true && before["pendingBatches"] == expected)
        val source = checkNotNull(database(projectId))
        val folder = File(context.filesDir, "firestore_recovery/${System.currentTimeMillis()}")
        check(folder.mkdirs())
        val sources = listOf(source, File(source.path + "-journal"), File(source.path + "-wal"),
            File(source.path + "-shm")) +
            (File(context.applicationInfo.dataDir, "shared_prefs").listFiles()?.toList() ?: emptyList())
        val manifest = mutableListOf<String>()
        for (file in sources.filter { it.isFile }) {
            val copy = File(folder, file.name)
            file.copyTo(copy, overwrite = false)
            val hash = digest(file)
            check(hash.contentEquals(digest(copy)))
            manifest += "${file.name}\t${copy.length()}\t${hash.joinToString("") { "%02x".format(it) }}"
        }
        check(File(folder, source.name).isFile)
        check(sources.any { it.name == "warloc_secure_storage.xml" && it.isFile })
        File(folder, "manifest.txt").writeText(manifest.joinToString("\n"))
        check(inspect(projectId)["pendingBatches"] == expected)
        return folder.path
    }
}
