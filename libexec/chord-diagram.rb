require 'fileutils'
require 'open3'
require 'pathname'
require 'rbconfig'
require 'tempfile'


# Metadata of the program
PROGRAM_NAME = "chord-diagram"
PROGRAM_VERSION = "0.1.1"


# Add .exe for executable on Windows
def executable_name(name)
  (RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/) ? (name + ".exe") : name
end

# Check whether a command exists or not.
def command?(name)
  [executable_name(name),
   *ENV['PATH'].split(File::PATH_SEPARATOR).map {
      |p| File.join(p, executable_name(name))
    }
  ].find {|f| File.executable?(f)}
end

# Convert a chord name to its LilyPond code.
def chord_code(chord)
  i = 0

  result = chord[0].downcase
  i += 1

  if "#" == chord[1]
    result += "is"
    i += 1
  elsif "b" == chord[1]
    result += "es"
    i += 1
  end

  result += "1"

  if "" != chord[i..-1]
    result += ":#{chord[i..-1]}"
  end

  result
end

def chords_code(chords)
  chords.map {|chord| chord_code chord }.join(" ")
end


# Check whether LilyPond exists on the system.
if not command?("lilypond") then
    STDERR.puts "No LilyPond on the system"
    exit 1
end

# Set the valid instruments in the program.
instruments = ["guitar", "guitalele", "ukulele", "baritone", "mandolin", "cajun", "mandola"]

# Template for the usage for the program.
usage = <<END_USAGE
#{PROGRAM_NAME} [option] [instrument] [chord] ...

Instruments:

#{instruments
    .map.with_index do |n, i|
      "* #{n}" + (i + 1 < instruments.length ? "\n" : "")
    end
    .join("")}

`baritone` means baritone ukuleles. `cajun` is mandolins with cajun tuning.

Chord Examples:

* C
* Am
* G7
* Dsus2

Each chord belongs to one command-line paramenter,
  separated by a space
END_USAGE

generate_code = false
diagram_size = 60
output_file_name = ""

# Parse the command-line parameters.
while ARGV.length > 0 do
  if "-v" == ARGV[0] or "--version" == ARGV[0]
    puts PROGRAM_VERSION
    exit 0
  elsif "-h" == ARGV[0] or "--help" == ARGV[0]
    puts usage
    exit 0
  elsif "-o" == ARGV[0] or "--output" == ARGV[0]
    ARGV.shift
    if 0 == ARGV.length
      STDERR.puts "No file name specified"
      exit 1
    end

    output_file_name = ARGV[0]
    ARGV.shift
  elsif "-ly" == ARGV[0] or "--lilypond" == ARGV[0]
    generate_code = true
    ARGV.shift  # Discard a parameter.
  elsif "-s" == ARGV[0] or "--size" == ARGV[0]
    ARGV.shift
    if 0 == ARGV.length
      STDERR.puts "No size specified"
      exit 1
    end

    diagram_size = ARGV[0].to_i
    if diagram_size <= 0
      STDERR.puts "Invalid size: #{diagram_size}"
      exit 1
    end
    ARGV.shift
  else
    break
  end
end

# Check whether the user input correct command-line parameter(s).
if ARGV.length < 2
  STDERR.puts "#{usage}"
  exit 1
end

instrument = ARGV[0]
chords = ARGV[1..-1]

# Check whether the user input a valid instrument.
if not instruments.any? {|n| instrument == n }
  STDERR.puts "Not a valid instrument: #{instrument}"
  STDERR.puts ""
  STDERR.puts "#{usage}"
  exit 1
end

# FIXME: Not really a strong regex to validate chord names.
chords.each do |chord|
  if not chord =~ /^[A-G][#b]?[A-Za-z0-9]*$/i
    STDERR.puts "Not a valid chord name: #{chord}"
    exit 1
  end
end

# Set the tuning and the fretboards given an instrument.
if ("guitar" == instrument) or ("guitalele" == instrument)
  tuning = "#guitar-tuning"
  predefined_fretboards = "\\include \"predefined-guitar-fretboards.ly\""
elsif ("mandolin" == instrument) or ("cajun" == instrument) or ("mandola" == instrument)
  tuning = "#mandolin-tuning"
  predefined_fretboards = "\\include \"predefined-mandolin-fretboards.ly\""
elsif ("ukulele" == instrument) or ("baritone" == instrument)
  tuning = "#ukulele-tuning"
  predefined_fretboards = "\\include \"predefined-ukulele-fretboards.ly\""
else
  STDERR.puts "Not a valid instrument: #{instrument}"
  exit 1
end

if "guitar" == instrument
  transposition = ""
elsif "ukulele" == instrument
  transposition = ""
elsif "mandolin" == instrument
  transposition = ""
elsif "cajun" == instrument
  transposition = "\\transpose f g "
elsif "mandola" == instrument
  transposition = "\\transpose c' g "
elsif "guitalele" == instrument
  transposition = "\\transpose c' g' "
elsif "baritone" == instrument
  transposition = "\\transpose c' f "
end

lilypond_preamble = <<END_LILYPOND_PREAMBLE
\\version "2.22.1"

#(set-global-staff-size #{diagram_size})

#(ly:set-option 'crop #t)
END_LILYPOND_PREAMBLE

# Template for the fretboard of a modern lute-family instrument.
lilypond_lute_code = <<END_LILYPOND_LUTE_CODE
#{lilypond_preamble}
chord = \\chordmode {
  #{chords_code chords}
}

#{predefined_fretboards}

\\score {
  <<
  \\new ChordNames {
    \\chord
  }

  \\new FretBoards {
    \\set Staff.stringTunings = #{tuning}
    #{transposition}\\chord
  }
  >>

  \\layout {}
}
END_LILYPOND_LUTE_CODE

# Generate LilyPond code instead of a chord diagram.
if generate_code
  if "" != output_file_name
    File.open(output_file_name, "w") do |file|
      file.write lilypond_lute_code
    end
  else
    puts lilypond_lute_code
  end

  exit 0
end

# Create a temporary LilyPond script.
lilypond_script = Tempfile.new([ 'lilypond-', '.ly' ])

# Write our code into the temporary file.
lilypond_script.write lilypond_lute_code

# Close the script to save our code.
lilypond_script.close

lilypond_script_path = lilypond_script.path

file_dirname = File.dirname(lilypond_script_path)
file_basename_no_ext = File.basename(lilypond_script_path, '.*')

lilypond_pdf_path = File.join(file_dirname, "#{file_basename_no_ext}.pdf")
lilypond_cropped_pdf_path = File.join(file_dirname, "#{file_basename_no_ext}.cropped.pdf")
lilypond_cropped_png_path = File.join(file_dirname, "#{file_basename_no_ext}.cropped.png")

# Set the output directory for LilyPond.
lilypond_command = "lilypond -o #{file_dirname} #{lilypond_script_path}"

# Compile the script by LilyPond.
stdout, stderr, status = Open3.capture3(lilypond_command)

# Create a fallback output file name if none.
if "" == output_file_name
  # Create a better name for baritone ukulele.
  if "baritone" == instrument
    output_file_name = "#{instrument}-ukulele-#{chords.join("-")}.png"
  else
    output_file_name = "#{instrument}-#{chords.join("-")}.png"
  end
end

# Copy the output PNG image.
if status.success?
  FileUtils.cp(lilypond_cropped_png_path, File.join(Dir.pwd, output_file_name))
else
  STDERR.puts stderr
end

# Delete the script and its output.
lilypond_script.unlink
File.unlink lilypond_pdf_path if File.exists? lilypond_pdf_path
File.unlink lilypond_cropped_pdf_path if File.exists? lilypond_cropped_pdf_path
File.unlink lilypond_cropped_png_path if File.exists? lilypond_cropped_png_path

# Return a status code if the command fails.
exit 1 if not status.success?
