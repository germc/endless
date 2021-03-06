#!/usr/bin/ruby

require "active_support/core_ext/hash/conversions"
require "plist"
require "json"
require "net/https"
require "uri"

HTTPS_E_TARGETS_PLIST = "Endless/Resources/https-everywhere_targets.plist"
HTTPS_E_RULES_PLIST = "Endless/Resources/https-everywhere_rules.plist"

URLBLOCKER_JSON = "urlblocker.json"
URLBLOCKER_TARGETS_PLIST = "Endless/Resources/urlblocker_targets.plist"

# in b64 for some reason
HSTS_PRELOAD_LIST = "https://chromium.googlesource.com/chromium/src/net/+/master/http/transport_security_state_static.json?format=TEXT"
HSTS_PRELOAD_HOSTS_PLIST = "Endless/Resources/hsts_preload.plist"

# convert all HTTPS Everywhere XML rule files into one big rules hash and write
# it out as a plist, as well as a standalone hash of target URLs -> rule names
# to another plist
def convert_https_e
  https_e_git_commit = `cd https-everywhere && git show -s`.split("\n")[0].
    gsub(/^commit /, "")[0, 12]

  if File.exists?(HTTPS_E_TARGETS_PLIST)
    if m = File.open(HTTPS_E_TARGETS_PLIST).gets.to_s.match(/Everywhere (.+) - /)
      if (m[1] == https_e_git_commit)
        return
      end
    end
  end

  rules = {}
  targets = {}

  Dir.glob(File.dirname(__FILE__) +
  "/https-everywhere/src/chrome/content/rules/*.xml").each do |f|
    hash = Hash.from_xml(File.read(f))

    raise "no ruleset" if !hash["ruleset"]

    if hash["ruleset"]["default_off"]
      next # XXX: should we store these?
    end

    raise "conflict on #{f}" if rules[hash["ruleset"]["name"]]

    rules[hash["ruleset"]["name"]] = hash

    hash["ruleset"]["target"].each do |target|
      if !target.is_a?(Hash)
        # why do some of these get converted into an array?
        if target.length != 2 || target[0] != "host"
          puts f
          raise target.inspect
        end

        target = { target[0] => target[1] }
      end

      if targets[target["host"][1]]
        raise "rules already exist for #{target["host"]}"
      end

      targets[target["host"]] = hash["ruleset"]["name"]
    end
  end

  File.write(HTTPS_E_TARGETS_PLIST,
    "<!-- generated from HTTPS Everywhere #{https_e_git_commit} - do not " +
      "directly edit this file -->\n" +
    targets.to_plist)

  File.write(HTTPS_E_RULES_PLIST,
    "<!-- generated from HTTPS Everywhere #{https_e_git_commit} - do not " +
      "directly edit this file -->\n" +
    rules.to_plist)
end

# convert JSON ruleset into a list of target domains and a list of rulesets
# with information URLs
def convert_urlblocker
  targets = {}

  JSON.parse(File.read(URLBLOCKER_JSON)).each do |company,domains|
    domains.each do |dom|
      targets[dom] = company
    end
  end

  File.write(URLBLOCKER_TARGETS_PLIST,
    "<!-- generated from #{URLBLOCKER_JSON} - do not directly edit this " +
      "file -->\n" +
    targets.to_plist)
end

def convert_hsts_preload
  domains = {}

  json = JSON.parse(Net::HTTP.get(URI(HSTS_PRELOAD_LIST)).unpack("m0").first)
  json["entries"].each do |entry|
    domains[entry["name"]] = {
      "include_subdomains" => !!entry["include_subdomains"]
    }
  end

  File.write(HSTS_PRELOAD_HOSTS_PLIST,
    "<!-- generated from #{HSTS_PRELOAD_LIST} - do not directly edit this " +
      "file -->\n" +
    domains.to_plist)
end

convert_https_e
convert_urlblocker
convert_hsts_preload
