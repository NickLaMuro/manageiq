# = Spec::Support::FakeAnsibleRepo
#
# Extracted from EmbeddedAnsible::AutomationManager::ConfigurationScriptSource
#
# Generates a dummy local git repository with a configurable file structure.
# The repo just needs to be given a repo_path and a file tree definition.
#
#     file_tree_definition = <<~TREE
#       roles/
#         foo/
#           tasks/
#             main.yml
#       requirements.yml
#       playbook.yml
#     TREE
#     FakeAnsibleRepo.generate "/path/to/my_repo", file_tree_definition
#
#     other_repo = FakeAnsibleRepo.new "/path/to/my/other_repo", file_tree_definition
#     other_repo.generate
#     other_repo.git_branch_create "patch_1"
#     other_repo.git_branch_create "patch_2"
#
#
# == File Tree Definition
#
# The file tree definition (file_struct) is just passed in as a plain text
# representation of a file structure in a pre-defined format, and converted to
# a data structure nested array for building out the git repo files.  See
# Spec::Support::FakeAnsibleRepo#parse_file_struct for more info.
#
# So for a single file repo with a `hello_world.yml` playbook, the definition
# as a HEREDOC string would be:
#
#     file_struct = <<~REPO
#       hello_world.yaml
#     REPO
#
# This will generate a repo with a single file called `hello_world.yml`.  For a
# more complex example:
#
#     file_struct = <<~REPO
#       azure_servers/
#         roles/
#           azure_stuffs/
#             tasks/
#               main.yml
#             defaults/
#               main.yml
#           requirements.yml
#         azure_playbook.yml
#       aws_servers/
#         roles/
#           s3_stuffs/
#             tasks/
#               main.yml
#             defaults/
#               main.yml
#           ec2_config/
#             tasks/
#               main.yml
#             defaults/
#               main.yml
#         aws_playbook.yml
#         s3_playbook.yml
#       openshift/
#         roles/
#       localhost/
#         requirements.yml
#         localhost_playbook.yml
#     REPO
#
# Which will generate the directory, where hash keys are directories, and
# values an array of strings (files), hashes (nested directories), or `nil`
# (empty dir).  As shown above, empty dirs like `openshift/roles/` can just be
# left as a empty key and that will be interpreted by yaml as `nil`.
#
#
# == Reserved file names/paths
#
# Most files with `.yml` or `.yaml` will be generated for some dummy content
# for a playbook:
#
#     - name: filename.yml
#       hosts: all
#       tasks:
#         - name: filename.yml Message
#           debug:
#             msg: "Hello World! (from filename.yml)"
#
# This is mostly to allow for testing playbook detecting code.  To the end,
# there are also "reserved" filenames that you can use to generate alternative
# dummy content that is not in a playbook format.
#
#
# === requirements.yml
#
# Regardless of where you put this file, if found, it will generate a sample
# `ansible-galaxy` requirements file.
#
#     - src: yatesr.timezone
#     - src: https://github.com/bennojoy/nginx
#     - src: https://github.com/bennojoy/nginx
#       version: master
#         name: nginx_role
#
#
# === roles/**/meta/main.yml
#
# Will generate a "Role Dependencies" yaml definition:
#
#     ---
#     dependencies:
#       - role: common
#         vars:
#           some_parameter: 3
#       - role: apache
#         vars:
#           apache_port: 80
#
#
# === extra_vars.yml, roles/**/vars/*.yml, and roles/**/defaults/*.yml
#
# Generates sample variable files
#
#     ---
#     var_1: foo
#     var_2: bar
#     var_3: baz
#

require "rugged"

require "yaml"
require "pathname"
require "fileutils"

module Spec
  module Support
    class FakeAnsibleRepo
      # Content format/borrowed from the ansible documentation
      #
      #   https://docs.ansible.com/ansible/latest/reference_appendices/galaxy.html#installing-multiple-roles-from-a-file
      REQUIREMENTS = <<~REQUIREMENTS.freeze
        - src: yatesr.timezone
        - src: https://github.com/bennojoy/nginx
        - src: https://github.com/bennojoy/nginx
          version: master
            name: nginx_role
      REQUIREMENTS

      # Content format/borrowed from the ansible documentation
      #
      #   https://docs.ansible.com/ansible/latest/user_guide/playbooks_reuse_roles.html#role-dependencies
      META_DATA = <<~ROLE_DEPS.freeze
        ---
        dependencies:
          - role: common
            vars:
              some_parameter: 3
          - role: apache
            vars:
              apache_port: 80
      ROLE_DEPS

      VAR_DATA = <<~VARS.freeze
        ---
        var_1: foo
        var_2: bar
        var_3: baz
      VARS

      attr_reader :file_struct, :repo_path, :repo, :index

      def self.generate(repo_path, file_struct)
        new(repo_path, file_struct).generate
      end

      def initialize(repo_path, file_struct)
        @repo_path   = Pathname.new(repo_path)
        @name        = @repo_path.basename
        @file_struct = parse_file_struct(file_struct)
      end

      def generate
        FileUtils.mkdir_p(repo_path)
        build_files_at(repo_path, file_struct)

        git_init
        git_add_all
        git_commit_initial
      end

      # Create a new branch (don't checkout)
      #
      #   $ git branch other_branch
      #
      def git_branch_create(new_branch_name)
        repo.create_branch(new_branch_name)
      end

      private

      # Parses a multi-line string as a file structure definition and return an
      # array of either single files or nested arrays/hashes.  The data
      # structures are as follows:
      #
      #   - Array:  Collection of directory contents (either Strings or Hashes)
      #   - String: A single filename
      #   - Hash:   A collection (usually one) directory (key) with entries (value)
      #
      # The format can be delivered in two forms.  Either pure yaml:
      #
      #     - path/:
      #       - to/:
      #         - dir:
      #           - foo
      #           - bar
      #           - baz
      #     - other/:
      #       - dir/:
      #
      # Or an plain text version that without some of the extra yaml chars added:
      #
      #     path/
      #       to/
      #         dir/
      #           foo
      #           bar
      #           baz
      #     other/
      #       dir/
      #
      #
      # Which is a cheeky trick with some regular expressions to allow for a
      # more human readable format.  Both still go through yaml, and the extra
      # formatting will be added only when missing.
      #
      # To use the second form, however, directories require a trailing slash,
      # where they are optional in the yaml form (the `:` takes care of that).
      #
      def parse_file_struct(file_struct)
        yaml_data = file_struct.gsub(/^(\s*)([a-zA-Z0-9\.])/, '\1- \2')
                               .gsub(/\/$/, '/:')
        YAML.safe_load(yaml_data)
      end

      # Builds a (nested) directory structure at the given path and file
      # structure definition.
      #
      # This method is called recursively, so `repo_relpath` and `file_struct`
      # might be in a nested partial state depending how deep the call of this
      # method has made it.
      #
      def build_files_at(repo_rel_path, file_struct)
        file_struct.each do |entry|
          case entry
          when Array  then build_files_at(repo_rel_path, entry)
          when Hash   then build_directory(repo_rel_path, entry)
          when String then build_file(repo_rel_path, entry)
          end
        end
      end

      # Generates a single directory (hash key)
      #
      # If there is entries (value), it defers back to `.build_files_at`,
      # otherwise if it is `nil` it represents a empty dir.
      #
      def build_directory(repo_rel_path, file_struct)
        file_struct.each do |dir, entries|
          new_dir = repo_rel_path.join(dir.sub(/\/$/, ''))

          FileUtils.mkdir_p(new_dir)
          build_files_at(new_dir, entries) if entries
        end
      end

      VAR_FILE_FNMATCHES = [
        "**/extra_vars.{yml,yaml}",
        "**/roles/*/vars/*.{yml,yaml}",
        "**/roles/*/defaults/*.{yml,yaml}"
      ].freeze

      # Gerates a single file
      #
      # If it is a reserved file name/path, then the contents are generated,
      # otherwise it will be a empty file.
      #
      def build_file(repo_rel_path, entry)
        full_path = repo_rel_path.join(entry)
        content   = if filepath_match?(full_path, "**/requirements.{yml,yaml}")
                      REQUIREMENTS
                    elsif filepath_match?(full_path, *VAR_FILE_FNMATCHES)
                      VAR_DATA
                    elsif filepath_match?(full_path, "**/roles/*/meta/main.{yml,yaml}")
                      META_DATA
                    elsif filepath_match?(full_path, "**/*.{yml,yaml}")
                      dummy_playbook_data_for(full_path.basename)
                    end

        File.write(full_path, content)
      end

      # Given a collection of glob based `File.fnmatch` strings, confirm
      # whether any of them match the given path.
      def filepath_match?(path, *acceptable_matches)
        acceptable_matches.any? { |match| path.fnmatch?(match, File::FNM_EXTGLOB) }
      end

      # Init new repo at local_repo
      #
      #   $ cd /tmp/clone_dir/hello_world_local && git init .
      #
      def git_init
        @repo  = Rugged::Repository.init_at(repo_path.to_s)
        @index = repo.index
      end

      # Add new files to index
      #
      #   $ git add .
      #
      def git_add_all
        index.add_all
        index.write
      end

      # Create initial commit
      #
      #   $ git commit -m "Initial Commit"
      #
      def git_commit_initial
        Rugged::Commit.create(
          repo,
          :message    => "Initial Commit",
          :parents    => [],
          :tree       => index.write_tree(repo),
          :update_ref => "HEAD"
        )
      end

      def dummy_playbook_data_for(filename)
        <<~PLAYBOOK_DATA
          - name: #{filename}
            hosts: all
            tasks:
              - name: #{filename} Message
                debug:
                  msg: "Hello World! (from #{filename})"
        PLAYBOOK_DATA
      end
    end
  end
end
