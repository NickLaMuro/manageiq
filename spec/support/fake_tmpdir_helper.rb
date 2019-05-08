# = fake_tmpdir_helper.rb
#
# Spec::Support::FakeTmpdirHelper is a helper module that is used to simulate a
# logical volume `/tmp` directory with limited disk space on the file system.
#
# To do this, it sets up a loopback device, which is just a zero'd out file
# (defaults to `manageiq/tmp/fake_fs.img`), and mounts it.  `Dir.tmpdir` is
# then overwritten to point to that newly mounted device, and it can
# transparently be used to be tested against using file system commands like
# normal (`df -P /fake_fs` for example).
#
# == Usage
#
# To use this lib, include it inside of your `describe` block:
#
#     describe 'Something' do
#       include Spec::Support::FakeTmpdirHelper
#     end
#
# Then use it by calling `with_fake_tmp` inside of the spec where you want to
# have a "fake tmp dir".  It will do all of the setup and cleanup within the
# block.
#
# Note:  This class is most likely **NOT** thread safe currently

require 'tmpdir'
require 'tempfile'
require 'pathname'
require 'sys-uname'
require 'active_support/all'

module Spec
  module Support
    module FakeTmpdirHelper
      PROJECT_TEMP_DIR = Pathname.new(File.expand_path("../../tmp", __dir__))

      module_function

      # The main function for setting up a loopback device.
      #
      #     with_fake_tmp do
      #       expect(Dir.tmpdir).to eq(fake_tmp_dir)
      #     end
      #
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
        # Linux:  Sets up the loop back device, and mounts it.
        #
        # Will effectively run the following:
        #
        #     $ losetup -f
        #     #=> /dev/loop0
        #     $ losetup /dev/loop0 tmp/fake_fs.img
        #     $ mkfs.ext4 /dev/loop0
        #     $ mount /dev/loop0 tmp/fake_fs
        #     $ chmod -R 777 tmp/fake_fs
        #
        # Note:  The `chmod` call is required since we are setting this up with
        # `sudo`, so we need to give write permissions to the world anything
        # within this dir so the `rspec` process can still write to it in the
        # specs.
        #
        def attach_tmp_fs
          @dev_disk = `losetup -f`.chomp.strip
          cmds = [
            "sudo losetup #{@dev_disk} #{tmp_fs_file}",
            "sudo mkfs.ext4 #{@dev_disk} 2>&1",
            "sudo mount #{@dev_disk} #{fake_tmp_dir}",
            "sudo chmod -R 777 #{fake_tmp_dir}"
          ]
          `#{cmds.join(" && ")}`
        end

        # Detaches the fake_fs from the file system.
        #
        # Need to both `umount` and `losetup -d` to release the loopback device
        #
        def detach_fake_fs
          `sudo umount #{@dev_disk} && sudo losetup -d #{@dev_disk}`
          @dev_disk = nil
        end
      when :macosx
        # OSX:  Sets up the loop back device, and mounts it.
        #
        # Will effectively run the following:
        #
        #     $ hdiutil attach -nomount tmp/fake_fs.img
        #     #=> /dev/disk2
        #     $ newfs_exfat /dev/disk2
        #     $ mount_exfat /dev/disk2 tmp/fake_tmp/
        #     ... # do stuff
        #     $ hdiutil detach /dev/disk2
        #
        def attach_tmp_fs
          @dev_disk = `hdiutil attach -nomount #{tmp_fs_file}`.chomp.strip
          `newfs_exfat #{@dev_disk} && mount_exfat #{@dev_disk} #{fake_tmp_dir}`
        end

        # Detaches the fake_fs from the file system.
        #
        # `hdiutil detach` will both umount and remove the loopback device.
        #
        def detach_fake_fs
          `hdiutil detach #{@dev_disk}`
          @dev_disk = nil
        end
      end
      # rubocop:enable Lint/DuplicateMethods

      # Builds the file if the size has changed or was not set.
      #
      # Removes any reference to `@tmp_fs_file` that might have existed
      # previously so the file is rebuilt.
      #
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
      #
      def patch_tmpdir
        @_old_dir ||= nil
        unless @_old_dir
          # Assign @fake_tmp_dir just incase it hasn't been already (avoiding a
          # recursive error here), prior to stubbing Dir
          Spec::Support::FakeTmpdirHelper.fake_tmp_dir

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
      #
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
      # extension that OSX recognizes for `hdiutil` to work
      #
      # (super dumb... I know...)
      #
      def tmp_fs_file
        return @tmp_fs_file if defined? @tmp_fs_file

        tmpfs = PROJECT_TEMP_DIR.join("fake_fs.img").to_s
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

      # Fetches or creates the location of the new faketmp directory.
      #
      # Since when redefining `Dir` we need to reference this module directly,
      # this make sure every time this method is called, we are setting the
      # memoized value on the module itself, and not for whatever instance this
      # module might be included in.
      #
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
