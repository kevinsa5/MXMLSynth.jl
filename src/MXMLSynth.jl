module MXMLSynth

using LibSndFile
using PortAudio
using SampledSignals
using MusicXML
using DataStructures

no_smoother(L,t) = 1
quadratic_smoother(L,t) = t^2 / (L/10000 + t^2)
cubic_smoother(L,t) = t^3 / (L/100000 + t^3)

function createSmoother(asymm_smoother, L)
  return t -> asymm_smoother(L,t) * asymm_smoother(L,L-t)
end

exp_fader(L,t) = exp(-t/L)

function createFader(unscaled_fader, L)
  return t -> unscaled_fader(L, t)
end

function calcFrequency(pitch::MusicXML.Pitch)
  # calculate the number of half-steps from A440 = A4
  id = pitch.octave * 12 + Int(pitch.step) + pitch.alter
  nhalfsteps = id - 58
  return 440 * 2 ^ (nhalfsteps/12) + 10*(rand()-0.5)
end

function saveBuffer(fpath::String, sb::SampledSignals.SampleBuf)
  LibSndFile.save(fpath, sb)
end

function playBuffer(sb::SampledSignals.SampleBuf,
                    stream::PortAudio.PortAudioStream = PortAudioStream("default"))
  write(stream, SampledSignals.SampleBufSource(sb))
end

function mergeBuffers(buffers::Array{SampleBuf,1})
  if length(buffers) == 1
    return buffers[1]
  end
  # assume all buffers have same sample_rate
  sample_rate = buffers[1].samplerate
  len = max(collect(length(b) for b in buffers)...)
  accum = SampleBuf(zeros(len), sample_rate)
  for (i,b) in enumerate(buffers)
    println(length(b))
    # buffers are not always the same length (# of samples)
    # is this a bug?  workaround is to zero-pad the end of the short buffers
    temp = vcat(b, SampleBuf(zeros(len - length(b)), sample_rate))
    accum += temp
  end
  return accum
end

function synthesizeMXML(tree::MusicXML.MXMLTree,
                        sample_rate = 4.41e4,
                        bpm = 120*40,
                        smoothing_function = quadratic_smoother
                        )
  buffers = SampleBuf[]
  for part in tree.parts
    buffer = synthesizePart(part, sample_rate, bpm, smoothing_function)
    push!(buffers, buffer)
  end
  return mergeBuffers(buffers)
end

# Returns a SampledSignals.SampleBuf
function synthesizePart(part::MusicXML.Part,
                         sample_rate = 4.41e4,
                         bpm = 120*20,
                         smoothing_function = quadratic_smoother
                         )
  buffer = Float64[]
  smoother = createSmoother(smoothing_function, 10/sample_rate)
  fader = createFader(exp_fader, 1)
  component(k,f,t) = sin(k*pi/8) * sin.(2*pi*k*f*t) / k^2
  samples_per_beat = round(sample_rate * 60 / bpm)
  for measure in part.measures
    for note in measure.notes
      num_samples = round(Int, samples_per_beat * note.duration / 4);
      if note.isrest
        append!(buffer, zeros(Float64, num_samples))
      else
        note_length = num_samples / sample_rate
        t = linspace(0, note_length, num_samples)
        freq = calcFrequency(note.pitch)
        y = zeros(Float64, length(t))
        for k in 1:15
          y += component(k, freq, t)
        end
        y = y .* smoother.(t) .* fader(t)
        append!(buffer, y)
      end
    end
  end
  return SampleBuf(buffer, sample_rate)
end

end
