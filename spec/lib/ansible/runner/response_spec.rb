describe Ansible::Runner::Response do
  subject { described_class.new(:base_dir => base_dir) }

  let(:base_dir)     { File.expand_path("../../..", stdout_file.path) } # triggers stdout_file
  let(:runner_dir)   { Dir.mktmpdir("runner_run") } # same as base_dir
  let(:stdout_file)  { File.open(stdout_filename, "w") { |f| f.write(stdout_lines); f } }
  let(:stdout_lines) { "" }

  let(:stdout_filename) do
    File.join(runner_dir, "artifacts", "result", "stdout").tap do |filename|
      FileUtils.mkdir_p(File.dirname(filename))
    end
  end

  after do
    FileUtils.rm_rf(runner_dir) if Dir.exist?(runner_dir)
  end

  describe "#parsed_stdout" do
    context "with no stdout file" do
      it "returns an empty array" do
        FileUtils.rm_rf(stdout_file.path)
        expect(subject.parsed_stdout).to eq([])
      end
    end

    context "with valid stdout (1 JSON object per line)" do
      let(:stdout_lines) do
        <<~LINES
          {"uuid": "d737fa4a", "counter": 1, "stdout": "", "start_line": 0, "end_line": 0}
          {"uuid": "080027c4", "counter": 2, "stdout": "\\r\\nPLAY [List Variables] **********************************************************", "start_line": 0, "end_line": 2}
          {"uuid": "080027c4", "counter": 3, "stdout": "\\r\\nTASK [Gathering Facts] *********************************************************", "start_line": 2, "end_line": 4}
          {"uuid": "7f4409f5", "counter": 4, "stdout": "", "start_line": 4, "end_line": 4}
        LINES
      end

      it "returns an array of only hashes" do
        expect(subject.parsed_stdout.all? { |line| line.kind_of?(Hash) }).to be_truthy
      end

      it "includes the expect 'stdout' keys" do
        expect(subject.parsed_stdout[0]['stdout']).to eq("")
        expect(subject.parsed_stdout[1]['stdout']).to eq("\r\nPLAY [List Variables] **********************************************************")
        expect(subject.parsed_stdout[2]['stdout']).to eq("\r\nTASK [Gathering Facts] *********************************************************")
        expect(subject.parsed_stdout[3]['stdout']).to eq("")
      end
    end

    context "with invalid stdout (mixed JSON and non-JSON lines)" do
      let(:stdout_lines) do
        <<~LINES
          {"uuid": "d737fa4a", "counter": 1, "stdout": "", "start_line": 0, "end_line": 0}
          {"uuid": "080027c4", "counter": 2, "stdout": "\\r\\nPLAY [List Variables] **********************************************************", "start_line": 0, "end_line": 2}
          PLAY [List Variables] **********************************************************
          {"uuid": "080027c4", "counter": 3, "stdout": "\\r\\nTASK [Gathering Facts] *********************************************************", "start_line": 2, "end_line": 4}
          TASK [Gathering Facts] *********************************************************
          {"uuid": "7f4409f5", "counter": 4, "stdout": "", "start_line": 4, "end_line": 4}
        LINES
      end

      it "returns an array of only hashes" do
        expect(subject.parsed_stdout.all? { |line| line.kind_of?(Hash) }).to be_truthy
      end

      it "includes the expect 'stdout' keys" do
        expect(subject.parsed_stdout[0]['stdout']).to eq("")
        expect(subject.parsed_stdout[1]['stdout']).to eq("\r\nPLAY [List Variables] **********************************************************")
        expect(subject.parsed_stdout[2]['stdout']).to eq("\r\nTASK [Gathering Facts] *********************************************************")
        expect(subject.parsed_stdout[3]['stdout']).to eq("")
      end
    end
  end
end
