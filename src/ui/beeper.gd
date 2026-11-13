extends AudioStreamPlayer
## Короткий звуковой сигнал: точка не поставлена или снята как недостижимая.
## Звук собирается из синуса при запуске, файлов не требует.

const MIX_RATE: int = 22050


func _ready() -> void:
	stream = _make_tone(330.0, 0.14)
	volume_db = -8.0


func beep() -> void:
	play()


func _make_tone(frequency: float, duration: float) -> AudioStreamWAV:
	var count: int = int(MIX_RATE * duration)
	var data: PackedByteArray = PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var envelope: float = minf(1.0, minf(i, count - i) / (MIX_RATE * 0.01))
		var value: int = int(sin(TAU * frequency * i / MIX_RATE) * 12000.0 * envelope)
		data.encode_s16(i * 2, value)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
