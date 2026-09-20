#!/usr/bin/env ruby
# frozen_string_literal: true

# Writes the Flatpak manifest from the gem cache, so every gem is pinned by
# path and checksum rather than fetched at build time. Run it after changing
# the Gemfile: `make manifest`.

require "json"
require "digest"

APP_ID = "io.github.alainm23.planify"
RUNTIME_VERSION = "49"
RUBY_VERSION_PIN = "3.4.9"

def cached_gems
  Dir.glob("vendor/cache/*.gem").sort.map do |path|
    {
      "type"   => "file",
      "path"   => path,
      "dest"   => "vendor/cache",
      "sha256" => Digest::SHA256.file(path).hexdigest,
    }
  end
end

# The network permission is what the sync backends need; the Evolution names
# are what calendar events need; owning the app's own name is what lets the
# CLI and the search provider reach a running window.
def finish_args
  [
    "--share=ipc",
    "--share=network",
    "--socket=fallback-x11",
    "--socket=wayland",
    "--device=dri",
    "--talk-name=org.freedesktop.Notifications",
    "--talk-name=org.freedesktop.secrets",
    "--talk-name=org.gnome.evolution.dataserver.Calendar8",
    "--talk-name=org.gnome.evolution.dataserver.Sources5",
    "--talk-name=org.gnome.evolution.dataserver.Subprocess.Backend.*",
    "--own-name=#{APP_ID}",
    "--talk-name=ca.desrt.dconf",
    "--filesystem=xdg-run/dconf",
    "--filesystem=~/.config/dconf:ro",
    "--env=DCONF_USER_CONFIG_DIR=.config/dconf",
  ]
end

# The GNOME runtime carries no Ruby, so it is built first and the app is
# installed against it.
def ruby_module
  {
    "name"        => "ruby",
    "buildsystem" => "autotools",
    "config-opts" => ["--disable-install-doc", "--enable-shared"],
    "sources"     => [
      {
        "type"   => "archive",
        "url"    => "https://cache.ruby-lang.org/pub/ruby/3.4/ruby-#{RUBY_VERSION_PIN}.tar.gz",
        "sha256" => ENV.fetch("RUBY_TARBALL_SHA256", ""),
      },
    ],
  }
end

def planify_module
  {
    "name"           => "planify",
    "buildsystem"    => "simple",
    "build-commands" => [
      "bundle config set --local deployment true",
      "bundle config set --local path vendor/bundle",
      "bundle install --local",
      "make install PREFIX=/app",
    ],
    "sources"        => [{ "type" => "dir", "path" => "." }] + cached_gems,
  }
end

def manifest
  {
    "app-id"          => APP_ID,
    "runtime"         => "org.gnome.Platform",
    "runtime-version" => RUNTIME_VERSION,
    "sdk"             => "org.gnome.Sdk",
    "command"         => "planify",
    "finish-args"     => finish_args,
    "modules"         => [ruby_module, planify_module],
  }
end

File.write("#{APP_ID}.json", "#{JSON.pretty_generate(manifest)}\n")
puts "Wrote #{APP_ID}.json with #{cached_gems.size} cached gems"
