# Speg Studio 🎬✨

<div align="center">
  <img src="assets/speg_logo.png" alt="Speg Studio Logo" width="380">
  <br>
  <p><strong>The Premier AI Short Video & Auto Clipping Suite</strong></p>
  <p>
    <a href="https://speghq-testing-facility.github.io/Speg-Studio/"><img src="https://img.shields.io/badge/Web%20Portal-GitHub%20Pages-8b5cf6" alt="Web Portal"></a>
    <a href="https://github.com/SpegHQ-Testing-Facility/Speg-Studio/raw/main/SpegStudio.exe"><img src="https://img.shields.io/badge/Download-SpegStudio.exe-success" alt="Download Executable"></a>
    <img src="https://img.shields.io/badge/Version-1.0.5-blue" alt="Version 1.0.5">
    <img src="https://img.shields.io/badge/Platform-Windows%2010%2F11-blue" alt="Windows 10/11">
  </p>
</div>

---

## 🚀 Overview

**Speg Studio** is a high-performance desktop video generation and clipping suite engineered for YouTube Shorts, TikTok, and Instagram Reels creators.

It combines autonomous AI scriptwriting, dual-character debate dialogue, expressive lip-synced PNGTubers, word-by-word kinetic animated subtitles, and direct video clipping into one sleek, hardware-accelerated studio interface.

### 🌐 Live Web Portal & Key System
- **Website & License Manager:** [https://speghq-testing-facility.github.io/Speg-Studio/](https://speghq-testing-facility.github.io/Speg-Studio/)
- **Supabase Database Project:** [suakvplhyllvgqntuhht](https://supabase.com/dashboard/project/suakvplhyllvgqntuhht)

---

## ✨ Key Features

- **✂️ Smart Stream & Video Clipping:**
  Paste any YouTube, Twitch, or Kick URL to instantly extract viral clips, convert them into vertical 9:16 videos, and sync captions.

- **🎭 Dual PNGTuber Dialogue Engine:**
  Render autonomous 2-character podcasts or debates with 13 emotional poses, automated background removal (`rembg`/ComfyUI), and voice-reactive mouth animation.

- **💬 Animated Kinetic Subtitles:**
  Word-by-word highlighted captions with dynamic bounce animations, custom color palettes, background glow, and Whisper speech-to-text accuracy.

- **🧠 Multi-Provider AI Scriptwriting:**
  Generate stories, facts, mysteries, and debates using free local models via Ollama (Llama 3, Mistral, Qwen) or cloud APIs (Claude 3.5 Sonnet, GPT-4o).

- **🖼️ Intelligent B-Roll Image Placement:**
  Mid-video context cards and illustrations generated locally via ComfyUI SDXL or pulled from curated image sequences.

- **🎙️ High-Fidelity Voice Synthesis:**
  Free local Kokoro-82M TTS alongside Microsoft Edge TTS and ElevenLabs.

- **🔐 Machine-Locked License Key System:**
  Hardware ID (HWID) locked license validation, password pre-hashing (SHA-256 with salt), license key regeneration, and creator social network powered by Supabase.

---

## 📥 Installation & Running

### Option 1: Standalone Executable (Recommended)
1. Download **[SpegStudio.exe](https://github.com/SpegHQ-Testing-Facility/Speg-Studio/raw/main/SpegStudio.exe)**.
2. Run `SpegStudio.exe` — no Python installation required!
3. On first launch, create an account and redeem your license key in the **Account & License** tab.

### Option 2: Run from Source
```bash
git clone https://github.com/SpegHQ-Testing-Facility/VideoGen.git
cd VideoGen
pip install -r requirements.txt
python gui.py
```

---

## 🗄️ Database Setup (Supabase)

To initialize or reset the license and authentication tables:

1. Open your Supabase project's SQL Editor:
   👉 **[Supabase SQL Editor (suakvplhyllvgqntuhht)](https://supabase.com/dashboard/project/suakvplhyllvgqntuhht/sql/new)**
2. Copy and paste the contents of [`supabase_schema.sql`](supabase_schema.sql).
3. Click **Run**.
4. The script creates all necessary tables (`speg_users`, `speg_keys`, `speg_friends`, `speg_messages`), Row Level Security (RLS) policies, and 20 PostgreSQL RPC functions.

### Initial Seeded License Keys
The schema automatically seeds the following keys for immediate use:
- `SPEG-STUDIO-VIP-2026` (VIP Tier, 365 Days)
- `SPEG-STUDIO-PRO-LIFETIME` (Lifetime Tier, Uncapped)
- `SPEG-STUDIO-TRIAL-30D` (Standard Tier, 30 Days)

---

## 🛠️ Tech Stack

- **UI Framework:** CustomTkinter, Tkinter, Pillow
- **Rendering & Video:** FFmpeg, PyAV, SoundFile, Faster-Whisper, CTranslate2
- **Backend & Auth:** Supabase PostgreSQL, Row Level Security, PostgREST RPC
- **AI Runtimes:** Ollama, ComfyUI, Kokoro-82M, Edge-TTS

---

<div align="center">
  <p>© 2026 SpegHQ. Built for creators.</p>
</div>
