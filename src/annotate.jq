# Turns the JSON records of cargo-project-tools into GitHub workflow commands.
# Input: the whole records file as one string (jq -R -s), one record per
# line. $workdir: the working-directory resolve.sh checked.
#
# Records carry text from locks, crates and the advisory database. Every
# value is escaped for workflow commands, and file, line and tool are only
# used when they have the shapes cargo-project-tools documents for them.

def data: tostring | gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A");
def prop: data | gsub(":"; "%3A") | gsub(","; "%2C");
def str: if . == null then "" else tostring end;
def list: if type == "array" then map(tostring) | join(", ") else str end;
def nonempty: type == "array" and length > 0;

def crate_name: type == "string" and test("^[A-Za-z0-9_-]{1,64}$");
def tool: if (.tool | crate_name) then .tool else null end;
def project_file:
  type == "string"
  and test("^(project-tools\\.toml|\\.project-tools/self-audit-ignore\\.toml|\\.project-tools/crates/[A-Za-z0-9_-]{1,64}/(Cargo\\.lock|build-review\\.toml|audit-ignore\\.toml))$");
def in_workdir: if $workdir == "." then . else $workdir + "/" + . end;
def positive_int: type == "number" and . >= 1 and floor == .;

def location:
  if (.file | project_file) then
    ["file=" + (.file | in_workdir | prop)]
    + (if (.line | positive_int) then ["line=" + (.line | tostring)] else [] end)
  else [] end;

def command($level; $title; $message):
  (location + ["title=" + ($title | prop)]) as $props
  | "::" + $level + " " + ($props | join(",")) + "::" + ($message | data);

def tool_title: (tool // "cargo-project-tools") + (if .tool_version then " " + (.tool_version | str) else "" end);

def advisory:
  command(
    if .severity == "error" then "error" else "warning" end;
    (.id | str) + " in " + (tool // "a tool");
    (.package | str) + "@" + (.package_version | str) + ": " + (.title | str)
    + (if (.patched | nonempty) then " (patched: " + (.patched | list) + ")" else "" end)
    + (if (.affected.os | nonempty) then " (only on: " + (.affected.os | list) + ")" else "" end)
    + (if tool == "cargo-project-tools" then
        ". Update setup-cargo-project-tools, or accept it in .project-tools/self-audit-ignore.toml."
      elif (.fix | type) == "string" then ". Fix: " + .fix
      else "" end));

def review_pending:
  command("error"; "Build review: " + (tool // "a tool");
    (.item.type | str) + " " + (.item.package | str)
    + (if .item.version then "@" + (.item.version | str) else "" end)
    + (if .item.path then " " + (.item.path | str) else "" end)
    + " has no decision"
    + (if (.item.previous.changed | nonempty) then " (changed: " + (.item.previous.changed | list) + ")" else "" end)
    + ". Decide it with `cargo project-tools review " + (tool // "<tool>")
    + "` where you work, then commit build-review.toml.");

def annotation($failed):
  if .kind == "advisory" then advisory
  elif .kind == "review-pending" then review_pending
  elif .kind == "target-missing" then
    command("error"; "Targets: " + (tool // "a tool");
      "This runner builds for " + (.targets | list) + ", which isn't in the tool's targets. Add it to project-tools.toml where you work, then commit it.")
  elif .kind == "build-failed" then command("error"; tool_title; .message | str)
  elif .kind == "error" and tool != null then
    if (tool as $t | $failed | index([$t])) then empty
    else command("error"; tool_title; .message | str) end
  elif .kind == "review-unused" then
    command("warning"; "Build review: " + (tool // "a tool");
      "Unused entry " + (.type | str) + " " + (.package | str) + (if .path then " " + (.path | str) else "" end)
      + ": it matches nothing the tool builds. Remove it where you work.")
  elif .kind == "ignore-unused" then
    command("warning"; "Audit ignore: " + (tool // "a tool"); "Ignore " + (.id | str) + " matched nothing. Remove it.")
  elif .kind == "ignore-expired" then
    command("warning"; "Audit ignore: " + (tool // "a tool");
      "Ignore " + (.id | str) + " expired on " + (.expires | str) + ". Renew or remove it.")
  elif .kind == "sfw-missing" then command("warning"; "Socket Firewall"; .message | str)
  elif .kind == "sandbox-missing" then command("warning"; "Build sandbox: " + (tool // "a tool"); .message | str)
  else empty end;

def known_kinds:
  ["advisory", "review-pending", "review-unused", "target-missing", "sandbox-missing",
   "built", "prepared", "build-failed", "up-to-date", "lock-change", "ignore-unused",
   "ignore-expired", "inspect", "ambiguous-dependency", "sfw-missing", "error", "summary"];

[split("\n")[] | select(test("\\S")) | (fromjson? // null)] as $all
| [$all[] | select(type == "object" and .version == 1)] as $records
| [$records[] | select(.kind == "build-failed") | tool | select(. != null)] as $failed
| [$records[] | annotation($failed)] as $found
| (if ($found | length) == 0 then
     [$records[] | select(.kind == "error" and tool == null) | command("error"; "cargo-project-tools"; .message | str)]
   else [] end) as $general
| (($all | length) - ($records | length)) as $skipped
| ([$records[] | select(.kind as $k | known_kinds | index([$k]) | not)] | length) as $unknown
| (reduce ($found + $general)[] as $line ([]; if any(.[]; . == $line) then . else . + [$line] end))[],
  (if $skipped > 0 then "::notice::Skipped \($skipped) lines from cargo-project-tools that aren't version 1 JSON records." else empty end),
  (if $unknown > 0 then "::notice::Skipped \($unknown) cargo-project-tools records of kinds this action doesn't know." else empty end)
