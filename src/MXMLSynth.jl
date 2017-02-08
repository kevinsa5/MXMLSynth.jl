module MXMLSynth

using LibSndFile
using PortAudio
using SampledSignals
using MusicXML

no_smoother(L,t) = 1
quadratic_smoother(L,t) = t^2 / (L/10000 + t^2)
cubic_smoother(L,t) = t^3 / (L/100000 + t^3)

function createSmoother(asymm_smoother, L)
  return t -> asymm_smoother(L,t) * asymm_smoother(L,L-t)
end

function calcFrequency(pitch::MusicXML.Pitch)
  # calculate the number of half-steps from A440 = A4
  id = pitch.octave * 12 + Int(pitch.step) + pitch.alter
  nhalfsteps = id - 58
  return 440 * 2 ^ (nhalfsteps/12)
end

function saveTrack(fpath::String, sb::SampledSignals.SampleBuf)
  LibSndFile.save(fpath, sb)
end

# Returns a SampledSignals.SampleBuf
function synthesizeTrack(tree::MusicXML.MXMLTree,
                         sample_rate = 4.41e4,
                         bpm = 120*30,
                         smoothing_function = quadratic_smoother)
  buffer = Float64[]
  smoother = createSmoother(smoothing_function, 10/sample_rate)
  samples_per_beat = round(sample_rate * 60 / bpm)
  for part in tree.parts
    for measure in part.measures
      for note in measure.notes
        num_samples = round(Int, samples_per_beat * note.duration / 4);
        if note.isrest
          append!(buffer, zeros(Float64, num_samples))
        else
          note_length = num_samples / sample_rate
          t = linspace(0, note_length, num_samples)
          freq = calcFrequency(note.pitch)
          y = 1.0 * sin.(2*pi*freq*t) .* smoother.(t)
          append!(buffer, y)
        end
      end
    end
  end
  return SampleBuf(buffer, sample_rate)
end

end
