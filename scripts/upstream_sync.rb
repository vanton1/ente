#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "open3"
require "pathname"
require_relative "lib/upstream_sync"

module EnteUpstreamSync
  class CLI
    def initialize(argv:, stdout: $stdout, stderr: $stderr, cwd: Dir.pwd)
      @argv = argv.dup
      @stdout = stdout
      @stderr = stderr
      @cwd = cwd
    end

    def run
      command = @argv.shift
      return usage("Missing command.") unless command
      return print_help if %w[-h --help help].include?(command)
      return usage("Unknown command: #{command}") unless command == "check"

      options = check_options(@argv)
      root = repository_root
      runner = Runner.new(root: root)
      report = Inspector.new(
        runner: runner,
        root: root,
        origin: options[:origin],
        upstream: options[:upstream],
        base_branch: options[:base_branch],
        fork_repository: options[:fork_repository],
        official_repository: options[:official_repository],
      ).check(fetch: options[:fetch])

      if options[:json]
        @stdout.puts(JSON.pretty_generate(report.to_h))
      else
        @stdout.puts(TextReport.render(report))
      end
      report.ready? ? 0 : EXIT_NOT_READY
    rescue OptionParser::ParseError => error
      usage(error.message)
    rescue CommandFailure => error
      @stderr.puts(error.message)
      EXIT_COMMAND_FAILED
    end

    private

    def check_options(argv)
      options = {
        fetch: true,
        json: false,
        origin: Inspector::DEFAULT_ORIGIN,
        upstream: Inspector::DEFAULT_UPSTREAM,
        base_branch: Inspector::DEFAULT_BASE_BRANCH,
        fork_repository: Inspector::DEFAULT_FORK_REPOSITORY,
        official_repository: Inspector::DEFAULT_OFFICIAL_REPOSITORY,
      }
      parser = OptionParser.new do |value|
        value.banner = "Usage: ./scripts/sync_upstream.sh check [options]"
        value.on("--[no-]fetch", "Fetch origin and upstream main (default: fetch)") { |setting| options[:fetch] = setting }
        value.on("--json", "Print a stable JSON readiness report") { options[:json] = true }
        value.on("--base BRANCH", "Fork base branch (default: main)") { |setting| options[:base_branch] = setting }
        value.on("--origin REMOTE", "Fork remote (default: origin)") { |setting| options[:origin] = setting }
        value.on("--upstream REMOTE", "Official remote (default: upstream)") { |setting| options[:upstream] = setting }
        value.on("--fork REPOSITORY", "Expected fork owner/repository") { |setting| options[:fork_repository] = setting }
        value.on("--official REPOSITORY", "Expected official owner/repository") { |setting| options[:official_repository] = setting }
        value.on("-h", "--help", "Show this help") do
          @stdout.puts(value)
          throw :help
        end
      end

      help_requested = catch(:help) do
        parser.parse!(argv)
        false
      end
      exit(0) if help_requested.nil?
      raise OptionParser::InvalidArgument, "Unexpected arguments: #{argv.join(" ")}" unless argv.empty?

      options
    end

    def repository_root
      stdout, stderr, status = Open3.capture3(
        "git",
        "rev-parse",
        "--show-toplevel",
        chdir: @cwd,
      )
      unless status.success?
        raise CommandFailure.new(
          ["git", "rev-parse", "--show-toplevel"],
          CommandResult.new(stdout: stdout, stderr: stderr, status: status.exitstatus),
        )
      end
      Pathname(stdout.strip).expand_path
    end

    def print_help
      @stdout.puts(<<~HELP)
        Guarded local synchronization of the Ente fork with official upstream.

        Usage:
          ./scripts/sync_upstream.sh check [options]

        Commands:
          check   Fetch and report exact upstream drift and local readiness

        Run './scripts/sync_upstream.sh check --help' for check options.
      HELP
      0
    end

    def usage(message)
      @stderr.puts(message)
      @stderr.puts("Run './scripts/sync_upstream.sh --help' for usage.")
      EXIT_USAGE
    end
  end
end

exit EnteUpstreamSync::CLI.new(argv: ARGV).run if $PROGRAM_NAME == __FILE__
