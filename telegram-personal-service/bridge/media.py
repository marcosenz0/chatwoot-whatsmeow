import asyncio
import json
import tempfile
from pathlib import Path

from telethon import types


async def run(*args):
    process = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    try:
        output, _ = await asyncio.wait_for(process.communicate(), 120)
    except asyncio.TimeoutError:
        process.kill()
        await process.communicate()
        raise
    return process.returncode, output


async def prepare(data, filename, mime, voice):
    attributes = [types.DocumentAttributeFilename(file_name=filename)]
    if not (voice or mime.startswith(('audio/', 'video/'))):
        return data, filename, mime, attributes
    with tempfile.TemporaryDirectory(prefix='telegram-media-') as directory:
        source = Path(directory) / 'source'
        source.write_bytes(data)
        if voice:
            target = Path(directory) / 'voice.ogg'
            code, _ = await run('ffmpeg', '-v', 'error', '-nostdin', '-y', '-i', str(source), '-vn', '-c:a', 'libopus', '-b:a', '48k', str(target))
            if code:
                return None
            source = target
            data, filename, mime = source.read_bytes(), 'voice.ogg', 'audio/ogg'
            attributes = [types.DocumentAttributeFilename(file_name=filename)]
        code, output = await run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(source))
        if code:
            return None if voice else (data, filename, mime, attributes)
        info = json.loads(output)
        duration = float(info.get('format', {}).get('duration') or 0)
        if voice or mime.startswith('audio/'):
            attributes.append(types.DocumentAttributeAudio(duration=int(duration), voice=voice))
        elif mime.startswith('video/'):
            video = next((stream for stream in info['streams'] if stream['codec_type'] == 'video'), None)
            if video:
                attributes.append(types.DocumentAttributeVideo(duration=duration, w=video['width'], h=video['height'], supports_streaming=True))
    return data, filename, mime, attributes
