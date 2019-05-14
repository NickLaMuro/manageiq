require 'tmpdir'
require 'tempfile'
require 'sys-uname'
require 'active_support/all'

module Spec
  module Support
    module FakeTmpdirHelper
      PROJECT_TEMP_DIR = Pathname.new(File.expand_path("../../tmp", __dir__))

      module_function

      def with_fake_tmp(size = fake_fs_size)
        build_file(size)
        attach_tmp_fs
        patch_tmpdir

        yield
      ensure
        detach_fake_fs
        unpatch_tmpdir
      end

      # rubocop:disable Lint/DuplicateMethods
      case Sys::Platform::IMPL
      when :linux
        # TODO:  Steps necessary for linux below
        #
        #     $ losetup /dev/loop0 /tmp/fake_tmp_fs
        #     $ mkfs.ext4 /dev/loop0
        #     $ mkdir /fake_tmp
        #     $ echo "#{fake_tmp_fstab_entry}" >> /etc/fstab
        #     $ mount /dev/loop0
        #     $ chmod -R 777 /fake_tmp
        #     $ chmod +t /fake_tmp
        #
        def attach_tmp_fs
        end

        def detach_fake_fs
        end
      when :macosx
        #
        #     $ hdiutil attach -nomount tmp/fake_fs.img
        #     #=> /dev/disk2
        #     $ newfs_exfat /dev/disk2
        #     $ mount_exfat /dev/disk2 tmp/fake_tmp/
        #     ... # do stuff
        #     $ hdiutil detach /dev/disk2
        #
        def attach_tmp_fs
          # TODO:  Error handling on these commands
          puts "hdiutil attach -nomount #{tmp_fs_file}"
          @dev_disk = `hdiutil attach -nomount #{tmp_fs_file}`.chomp.strip
          puts "newfs_exfat #{@dev_disk} && mount_exfat #{@dev_disk} #{fake_tmp_dir}"
          `newfs_exfat #{@dev_disk} && mount_exfat #{@dev_disk} #{fake_tmp_dir}`
        end

        def detach_fake_fs
          `hdiutil detach #{@dev_disk}`
          @dev_disk = nil
        end
      end
      # rubocop:enable Lint/DuplicateMethods

      def build_file(size)
        if update_size?(size)
          @tmp_fs_file = nil
          tmp_fs_file
        end
      end

      # Create a new class for `Dir`, but first removing the normal Dir
      # constant from the global namespace, creating a new class that inherits
      # from the original constant, re-writes Dir.tmpdir, and attaches itself
      # inplace of Dir in the global namespace.
      #
      # Choosing **NOT** to use RSpec's `stub_const` so this can be run as a
      # regular ruby script (for easier testing)
      def patch_tmpdir
        @_old_dir ||= nil
        unless @_old_dir
          @_old_dir = Dir
          Object.send(:remove_const, :Dir)

          _new_dir = Class.new(@_old_dir)
          def _new_dir.tmpdir
            Spec::Support::FakeTmpdirHelper.fake_tmp_dir
          end
          Object.const_set(:Dir, _new_dir)
        end
      end

      # Removes the existing (fake) `Dir` constant, and re-attaches the
      # original
      def unpatch_tmpdir
        @_old_dir ||= nil
        if @_old_dir
          Object.send(:remove_const, :Dir)
          Object.const_set(:Dir, Class.new(@_old_dir))
          @_old_dir = nil
        end
      end

      # Write a null byte filled file, and will truncate any existing contents
      # (a property of using "w" as the file mode).
      #
      # Unix Equivalent:
      #
      #   dd if=/dev/zero of=filename bs=1K count=1024
      #
      # Note: To work with OSX machines, this has to be a .img file, or some
      # extension that OSX recognizes (super dumb... I know...)
      #
      def tmp_fs_file
        return @tmp_fs_file if defined? @tmp_fs_file

        tmpfs = PROJECT_TEMP_DIR.join("fake_fs.img").to_s
        puts "creating #{tmpfs}..."
        base_chunk = "\x00" * 1.kilobyte

        File.open(tmpfs, "w") do |file|
          # Add data in 1KB chunks
          (fake_fs_size / 1.kilobyte).times do
            file << base_chunk
          end

          # Add remainder data to tmp file (if any)
          file << "\x00" * (fake_fs_size % 1.kilobyte)
        end

        @tmp_fs_file = tmpfs
      end

      def fake_tmp_dir
        if self == Spec::Support::FakeTmpdirHelper
          @fake_tmp_dir ||= Dir.mktmpdir("fake_tmp")
        else
          Spec::Support::FakeTmpdirHelper.fake_tmp_dir
        end
      end

      def fake_fs_size
        @size ||= 1.megabyte
      end

      def update_size?(size)
        @size = size if @size != size
      end
    end
  end
end
