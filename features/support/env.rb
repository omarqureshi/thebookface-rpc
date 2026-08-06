# frozen_string_literal: true

# Cucumber environment.
#
# The biggest change from the Rails app's suite: there is no `cucumber/rails`,
# and no rack_test. The old suite could drive server-rendered HTML in-process;
# here the UI is a React SPA, so nothing exists until JavaScript has run. Every
# scenario therefore runs in a real browser against two live processes:
#
#   :9292  the Rack API   (all services in one process)
#   :5173  the Vite dev server, proxying /rpc to the API
#
#   script/cucumber.sh          # starts both, runs the suite, tears down
#
# Steps still seed through the Dynamoid models directly, exactly as before —
# that part of the old suite ported unchanged, because the models did.

require "capybara/cucumber"
require "capybara/cuprite"
require "rspec/expectations"

ENV["DYNAMODB_ENDPOINT"] ||= "http://localhost:8000"
require_relative "../../config/boot"

APP_HOST = ENV.fetch("BOOKFACE_UI", "http://localhost:5173")
API_HOST = ENV.fetch("BOOKFACE_API", "http://localhost:9292")

# Downloaded by `npx @puppeteer/browsers install chrome@stable` into web/chrome.
# Falls back to whatever ferrum can autodetect.
def chrome_path
  return ENV["CHROME_PATH"] if ENV["CHROME_PATH"]

  # File.file? as well as executable?: @puppeteer/browsers nests the download
  # under <path>/chrome/<platform>-<build>/, so the glob also matches the
  # DIRECTORY web/chrome/chrome -- and a directory is "executable", meaning
  # searchable. Picking it gives Errno::EACCES at the first step of every
  # scenario.
  Dir[File.expand_path("../../web/chrome/**/chrome", __dir__)]
    .find { |p| File.file?(p) && File.executable?(p) }
end

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [1200, 900],
    headless: true,
    process_timeout: 30,
    timeout: 30,
    browser_path: chrome_path,
    browser_options: {
      "no-sandbox" => nil,
      "disable-gpu" => nil,
      "disable-dev-shm-usage" => nil
    }
  )
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite
Capybara.app_host = APP_HOST
# Capybara must not boot a Rack app of its own: the thing under test is a
# browser talking to servers we started.
Capybara.run_server = false
# React renders asynchronously, so every matcher needs to be a waiting one.
Capybara.default_max_wait_time = 8
# The UI labels controls with aria-label rather than <label for>, which is the
# right thing for a screen reader and invisible to Capybara unless this is on.
Capybara.enable_aria_label = true

# Fail fast and legibly when the servers aren't up, rather than with a wall of
# Ferrum navigation errors.
require "net/http"
[["UI", APP_HOST], ["API", "#{API_HOST}/up"]].each do |name, url|
  Net::HTTP.get_response(URI(url))
rescue StandardError => e
  abort "#{name} is not reachable at #{url} (#{e.class}). Run script/cucumber.sh, " \
        "or start both servers yourself."
end
