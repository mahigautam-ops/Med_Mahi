package com.example.med_caller

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.*

class CallRecordingService {

    companion object {
        private const val TAG = "CallRecording"
        private const val SAMPLE_RATE = 44100
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private var isRecording = false
    private var currentFile: File? = null

    fun startRecording(context: Context): String? {
        if (isRecording) return null

        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (bufferSize == AudioRecord.ERROR_BAD_VALUE || bufferSize == AudioRecord.ERROR) {
            Log.e(TAG, "Invalid audio configuration")
            return null
        }

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize * 2
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "RECORD_AUDIO permission not granted")
            return null
        }

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord failed to initialize")
            audioRecord?.release()
            audioRecord = null
            return null
        }

        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val dir = File(context.filesDir, "call_recordings")
        dir.mkdirs()
        val wavFile = File(dir, "call_$timestamp.wav")
        currentFile = wavFile

        isRecording = true
        audioRecord?.startRecording()

        recordingThread = Thread {
            writeWavData(bufferSize, wavFile)
        }.also { it.start() }

        Log.d(TAG, "Recording started: ${wavFile.absolutePath}")
        return wavFile.absolutePath
    }

    fun stopRecording(): String? {
        if (!isRecording) return null
        isRecording = false

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        recordingThread?.join(2000)
        recordingThread = null

        val filePath = currentFile?.absolutePath
        Log.d(TAG, "Recording stopped: $filePath")
        return filePath
    }

    fun isRecording() = isRecording

    fun getRecordingFile(): File? = currentFile

    private fun writeWavData(bufferSize: Int, outFile: File) {
        val buffer = ShortArray(bufferSize / 2)
        var totalBytes = 0

        FileOutputStream(outFile).use { fos ->
            fos.write(ByteArray(44))

            while (isRecording) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) {
                    val byteBuffer = ByteArray(read * 2)
                    for (i in 0 until read) {
                        byteBuffer[i * 2] = (buffer[i].toInt() and 0xFF).toByte()
                        byteBuffer[i * 2 + 1] = (buffer[i].toInt() shr 8 and 0xFF).toByte()
                    }
                    fos.write(byteBuffer)
                    totalBytes += byteBuffer.size
                }
            }

            writeWavHeader(outFile, totalBytes)
        }
    }

    private fun writeWavHeader(file: File, totalDataBytes: Int) {
        val totalFileBytes = totalDataBytes + 36
        val header = ByteArray(44)

        header[0] = 'R'.code.toByte(); header[1] = 'I'.code.toByte()
        header[2] = 'F'.code.toByte(); header[3] = 'F'.code.toByte()
        writeInt(header, 4, totalFileBytes)
        header[8] = 'W'.code.toByte(); header[9] = 'A'.code.toByte()
        header[10] = 'V'.code.toByte(); header[11] = 'E'.code.toByte()

        header[12] = 'f'.code.toByte(); header[13] = 'm'.code.toByte()
        header[14] = 't'.code.toByte(); header[15] = ' '.code.toByte()
        writeInt(header, 16, 16)
        writeShort(header, 20, 1)
        writeShort(header, 22, 1)
        writeInt(header, 24, SAMPLE_RATE)
        writeInt(header, 28, SAMPLE_RATE * 2)
        writeShort(header, 32, 2)
        writeShort(header, 34, 16)

        header[36] = 'd'.code.toByte(); header[37] = 'a'.code.toByte()
        header[38] = 't'.code.toByte(); header[39] = 'a'.code.toByte()
        writeInt(header, 40, totalDataBytes)

        RandomAccessFile(file, "rw").use { raf ->
            raf.seek(0)
            raf.write(header)
        }
    }

    private fun writeInt(buffer: ByteArray, offset: Int, value: Int) {
        buffer[offset] = (value and 0xFF).toByte()
        buffer[offset + 1] = (value shr 8 and 0xFF).toByte()
        buffer[offset + 2] = (value shr 16 and 0xFF).toByte()
        buffer[offset + 3] = (value shr 24 and 0xFF).toByte()
    }

    private fun writeShort(buffer: ByteArray, offset: Int, value: Int) {
        buffer[offset] = (value and 0xFF).toByte()
        buffer[offset + 1] = (value shr 8 and 0xFF).toByte()
    }
}
