#!/usr/bin/env ruby

require "set"
require "yaml"

class WorkflowSecurityChecker
  FORK_GUARD = "github.repository == 'vanton1/ente'".freeze
  ALLOWED_RUNNERS = %w[ubuntu-24.04 macos-26].to_set.freeze
  SENSITIVE_TRIGGERS = %w[
    pull_request_target
    issue_comment
    pull_request_review_comment
    discussion_comment
    workflow_run
  ].to_set.freeze
  WORKFLOW_RULES = {
    ".github/workflows/codeql.yml" => {
      triggers: %w[pull_request schedule workflow_dispatch],
      permissions: { "contents" => "read", "security-events" => "write" },
    },
    ".github/workflows/dependency-review.yml" => {
      triggers: %w[pull_request],
      permissions: { "contents" => "read" },
    },
    ".github/workflows/self-hosted-mobile-linux.yml" => {
      triggers: %w[pull_request workflow_dispatch],
      permissions: { "contents" => "read" },
    },
    ".github/workflows/self-hosted-mobile-macos.yml" => {
      triggers: %w[pull_request workflow_dispatch],
      permissions: { "contents" => "read" },
    },
    ".github/workflows/upstream-sync-drift.yml" => {
      triggers: %w[schedule workflow_dispatch],
      permissions: { "contents" => "read", "issues" => "write" },
    },
    ".github/workflows/workflow-security-checks.yml" => {
      triggers: %w[pull_request],
      permissions: { "contents" => "read" },
    },
  }.freeze
  ALLOWED_ACTION_FILES = Set[
    ".github/actions/setup-flutter/action.yml",
  ].freeze
  ALLOWED_ENVIRONMENTS = {
    ".github/workflows/workflow-security-checks.yml" => {
      "workflow-security-checks" => "workflow-change-approval",
    },
  }.freeze
  USES_REF = %r{\A([A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._/-]+)?)@(\S+)\z}.freeze
  FULL_SHA = /\A[0-9a-fA-F]{40}\z/.freeze

  def initialize(root: Dir.pwd, out: $stdout)
    @root = File.expand_path(root)
    @out = out
    @violations = Hash.new { |hash, key| hash[key] = [] }
  end

  def run
    workflow_paths = relative_glob(".github/workflows/*.{yml,yaml}")
    action_paths = relative_glob(".github/actions/**/*.{yml,yaml}")

    validate_allowlist("workflow", workflow_paths.to_set, WORKFLOW_RULES.keys.to_set)
    validate_allowlist("action", action_paths.to_set, ALLOWED_ACTION_FILES)

    (workflow_paths + action_paths).each do |path|
      document = workflow_yaml(path)
      validate_uses(path, document)
      validate_checkout_credentials(path, document)
      validate_secret_references(path)
    end

    workflow_paths.each do |path|
      rule = WORKFLOW_RULES[path]
      next unless rule

      workflow = workflow_yaml(path)
      validate_triggers(path, workflow, rule.fetch(:triggers))
      validate_permissions(path, workflow, rule.fetch(:permissions))
      validate_jobs(path, workflow)
    end

    print_report(workflow_paths.length + action_paths.length)
    @violations.empty? ? 0 : 1
  end

  private

  def relative_glob(pattern)
    Dir.glob(File.join(@root, pattern)).sort.map do |path|
      path.delete_prefix("#{@root}/")
    end
  end

  def workflow_yaml(path)
    YAML.safe_load(File.read(File.join(@root, path)), aliases: true) || {}
  rescue Psych::Exception => e
    add(:yaml, "#{path}: #{e.message}")
    {}
  end

  def trigger_names(workflow)
    events = workflow["on"] || workflow[true]
    return [events] if events.is_a?(String)
    return events.grep(String) if events.is_a?(Array)
    return events.keys.map(&:to_s) if events.is_a?(Hash)

    []
  end

  def validate_allowlist(kind, actual, expected)
    (actual - expected).sort.each do |path|
      add(:allowlist, "Unexpected #{kind}: #{path}")
    end
    (expected - actual).sort.each do |path|
      add(:allowlist, "Missing #{kind}: #{path}")
    end
  end

  def validate_triggers(path, workflow, expected)
    actual = trigger_names(workflow).to_set
    sensitive = actual & SENSITIVE_TRIGGERS
    sensitive.each { |trigger| add(:triggers, "#{path}: privileged trigger #{trigger}") }
    return if actual == expected.to_set

    add(:triggers, "#{path}: expected #{expected.sort.join(', ')}, found #{actual.to_a.sort.join(', ')}")
  end

  def validate_permissions(path, workflow, expected)
    actual = stringify_hash(workflow["permissions"] || {})
    return if actual == expected

    add(:permissions, "#{path}: expected #{expected.inspect}, found #{actual.inspect}")
  end

  def validate_jobs(path, workflow)
    jobs = workflow["jobs"]
    unless jobs.is_a?(Hash) && !jobs.empty?
      add(:jobs, "#{path}: no jobs declared")
      return
    end

    jobs.each do |name, job|
      unless job.is_a?(Hash)
        add(:jobs, "#{path}: job #{name} is not a mapping")
        next
      end

      condition = job["if"].to_s
      unless condition.include?(FORK_GUARD) && !condition.include?("||")
        add(:jobs, "#{path}: job #{name} must fail closed on #{FORK_GUARD}")
      end

      runner = job["runs-on"]
      add(:jobs, "#{path}: job #{name} uses unapproved runner #{runner.inspect}") unless ALLOWED_RUNNERS.include?(runner)

      timeout = job["timeout-minutes"]
      unless timeout.is_a?(Integer) && timeout.positive? && timeout <= 60
        add(:jobs, "#{path}: job #{name} needs a timeout from 1 to 60 minutes")
      end

      add(:permissions, "#{path}: job #{name} must not override top-level permissions") if job.key?("permissions")
      validate_environment(path, name, job)
    end
  end

  def validate_environment(path, job_name, job)
    expected = ALLOWED_ENVIRONMENTS.fetch(path, {})[job_name]
    environment = job["environment"]
    actual = environment.is_a?(Hash) ? environment["name"] : environment
    return if actual == expected

    add(:environments, "#{path}: job #{job_name} expected environment #{expected.inspect}, found #{actual.inspect}")
  end

  def validate_uses(path, document)
    uses_values(document).each do |uses|
      if uses.start_with?("./")
        local_action = "#{uses.delete_prefix('./')}/action.yml"
        add(:actions, "#{path}: unapproved local action #{uses}") unless ALLOWED_ACTION_FILES.include?(local_action)
        next
      end

      action, ref = uses.match(USES_REF)&.captures
      unless action
        add(:actions, "#{path}: unsupported action reference #{uses}")
        next
      end
      add(:actions, "#{path}: unpinned action #{action}@#{ref}") unless ref.match?(FULL_SHA)
    end
  end

  def validate_checkout_credentials(path, document)
    step_nodes(document).each do |step|
      uses = step["uses"]
      next unless uses.is_a?(String) && uses.start_with?("actions/checkout@")

      value = step.fetch("with", {})["persist-credentials"]
      add(:credentials, "#{path}: actions/checkout must set persist-credentials: false") unless value == false
    end
  end

  def validate_secret_references(path)
    source = File.read(File.join(@root, path))
    add(:secrets, "#{path}: repository or environment secret reference is forbidden") if source.match?(/\bsecrets\s*\./)
  end

  def uses_values(node)
    case node
    when Hash
      node.flat_map do |key, value|
        current = key.to_s == "uses" && value.is_a?(String) ? [value] : []
        current + uses_values(value)
      end
    when Array
      node.flat_map { |value| uses_values(value) }
    else
      []
    end
  end

  def step_nodes(node)
    case node
    when Hash
      current = node.key?("uses") ? [node] : []
      current + node.values.flat_map { |value| step_nodes(value) }
    when Array
      node.flat_map { |value| step_nodes(value) }
    else
      []
    end
  end

  def stringify_hash(value)
    return {} unless value.is_a?(Hash)

    value.each_with_object({}) do |(key, item), output|
      output[key.to_s] = item.to_s
    end
  end

  def add(category, message)
    @violations[category] << message
  end

  def print_report(checked_count)
    failed = !@violations.empty?
    @out.puts "Workflow Security Checks: #{failed ? 'Failed' : 'Passed'}"
    @out.puts "Checked #{checked_count} approved workflow/action files."
    return unless failed

    @violations.keys.sort.each do |category|
      @out.puts
      @out.puts "#{category.to_s.capitalize} violations:"
      @violations[category].sort.each { |violation| @out.puts "- #{violation}" }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  abort("Usage: #{$PROGRAM_NAME}") unless ARGV.empty?
  exit WorkflowSecurityChecker.new.run
end
