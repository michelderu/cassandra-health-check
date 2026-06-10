#!/usr/bin/env bash
# Patch Montecristo log parsing for Cassandra 4.x / 5.x logback patterns and timestamps.
set -euo pipefail

MONTECRISTO_SRC="${1:-/opt/montecristo-src}"
LOG_REGEX="${MONTECRISTO_SRC}/montecristo/src/main/kotlin/com/datastax/montecristo/logs/LogRegex.kt"
LOG_ENTRY="${MONTECRISTO_SRC}/montecristo/src/main/kotlin/com/datastax/montecristo/logs/LogEntry.kt"

patch_logregex() {
  if grep -q 'modernCassandraLogbackPattern' "${LOG_REGEX}"; then
    echo "LogRegex.kt already patched."
    return 0
  fi

  LOG_REGEX_FILE="${LOG_REGEX}" python3 <<'PY'
import os
import pathlib

path = pathlib.Path(os.environ["LOG_REGEX_FILE"])
text = path.read_text()

needle = """            val defaultLogbackPattern = "%-5level [%thread] %date{ISO8601} %F:%L - %msg%n"


            // Default Pattern"""

replacement = """            val defaultLogbackPattern = "%-5level [%thread] %date{ISO8601} %F:%L - %msg%n"
            val modernCassandraLogbackPattern =
                "%-5level [%thread] %date{\\"yyyy-MM-dd'T'HH:mm:ss,SSS\\", UTC} %F:%L - %msg%n"


            // Default Pattern"""

if needle not in text:
    raise SystemExit(f"LogRegex.kt layout changed; cannot patch {path}")

text = text.replace(needle, replacement, 1)

needle = """                return defaultRegex()
            } else {
                // replace the markers with the regex's for the section"""

replacement = """                return defaultRegex()
            } else if (logbackPattern.trim() == modernCassandraLogbackPattern) {
                val regex = Regex(
                    \"\"\"^\\s*(\\w+)\\s*\\[.*?]\\s*(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2},\\d+)\\s+(.*)\"\"\",
                    RegexOption.DOT_MATCHES_ALL
                )
                val groupMappings = mapOf(
                    LogEntryGroupings.LEVEL to 1,
                    LogEntryGroupings.DATE to 2,
                    LogEntryGroupings.MESSAGE to 3
                )
                return LogRegex(regex, groupMappings)
            } else {
                // replace the markers with the regex's for the section"""

if needle not in text:
    raise SystemExit("LogRegex.kt branch layout changed; cannot patch modern pattern handler")

text = text.replace(needle, replacement, 1)

needle = """                val potentialRegex = logbackPattern
                    .replace("%-5level", "(\\\\w+)")
                    .replace("[%thread]", "\\\\[.*?]")
                    .replace("%date{ISO8601}", "([^,]*),\\\\d*")"""

replacement = """                val potentialRegex = logbackPattern
                    .replace("%-5level", "(\\\\w+)")
                    .replace("[%thread]", "\\\\[.*?]")
                    .replace(Regex(\"\"\"%date\\\\{[^}]*}\"\"\"), \"(\\\\d{4}-\\\\d{2}-\\\\d{2}T\\\\d{2}:\\\\d{2}:\\\\d{2},\\\\d+)\")
                    .replace("%date{ISO8601}", "([^,]*),\\\\d*")"""

if needle not in text:
    raise SystemExit("LogRegex.kt replacement chain changed; cannot patch %date handler")

text = text.replace(needle, replacement, 1)
path.write_text(text)
print(f"Patched {path}")
PY
}

patch_logentry() {
  if grep -q 'parseIsoLogTimestamp' "${LOG_ENTRY}"; then
    echo "LogEntry.kt already patched."
    return 0
  fi

  LOG_ENTRY_FILE="${LOG_ENTRY}" python3 <<'PY'
import os
import pathlib

path = pathlib.Path(os.environ["LOG_ENTRY_FILE"])
text = path.read_text()

needle = """        val formatter: DateTimeFormatter = DateTimeFormatter.ofPattern(internalFormat)

        fun fromString(line: String, logRegex : LogRegex): LogEntry {"""

replacement = """        val formatter: DateTimeFormatter = DateTimeFormatter.ofPattern(internalFormat)

        private fun parseIsoLogTimestamp(isoFormatDate: String): Date {
            return when {
                'T' in isoFormatDate ->
                    SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss,SSS").parse(isoFormatDate)
                else ->
                    SimpleDateFormat("yyyy-MM-dd HH:mm:ss").parse(isoFormatDate)
            }
        }

        fun fromString(line: String, logRegex : LogRegex): LogEntry {"""

if needle not in text:
    raise SystemExit(f"LogEntry.kt layout changed; cannot patch {path}")

text = text.replace(needle, replacement, 1)

needle = '                    val parsedDate = SimpleDateFormat("yyyy-MM-dd HH:mm:ss").parse(isoFormatDate)'
replacement = '                    val parsedDate = parseIsoLogTimestamp(isoFormatDate!!)'

if needle not in text:
    raise SystemExit("LogEntry.kt timestamp parse line changed; cannot patch")

text = text.replace(needle, replacement, 1)
path.write_text(text)
print(f"Patched {path}")
PY
}

patch_logregex
patch_logentry
echo "Montecristo log patches applied."
