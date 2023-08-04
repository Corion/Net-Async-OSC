load_sample :bd_fat
load_sample :drum_cymbal_closed
load_sample :drum_snare_soft

live_loop :bd do
  use_real_time
  amp, rest = sync "/osc*/trigger/bd"
  sample :bd_fat, amp: amp
end

live_loop :hh do
  use_real_time
  amp, rest = sync "/osc*/trigger/hh"
  sample  :drum_cymbal_closed, amp: amp
end

live_loop :sn do
  use_real_time
  amp, rest = sync "/osc*/trigger/sn"
  sample :drum_snare_soft, amp: amp
end

use_synth :tb303
use_synth :sine

#with_fx :echo do |fx_echo|
live_loop :chords do
  use_real_time
  note, harmony =  sync "/osc*/trigger/chord"
  synth :sine, note: chord(note, harmony)
end
#end

use_synth :bass_foundation
live_loop :bass do
  use_real_time
  note =  sync "/osc*/trigger/bass"
  synth :bass_foundation, note: note, release: 1, amp: 0.75
end


use_synth :organ_tonewheel
melody = play :C4, sustain: 60*60*2
melody.pause
#with_fx :reverb, mix: 0.1 do
with_fx :wobble,cutoff_max: 90, phase: 3, filter: 1 do
  live_loop :tb303 do
    use_real_time
    note, = sync "/osc*/trigger/melody"
    #synth :organ_tonewheel, note: note, release: 0.01, decay: 0.5
    melody.control note: note
    melody.run
  end
end
