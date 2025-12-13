# openpaperwork-snap
This repository contains an **unofficial Snap package** of [OpenPaperwork](https://gitlab.gnome.org/World/OpenPaperwork/paperwork), a personal document management application for Linux.

## Features

- Scan, organize, and search documents efficiently.
- Built-in Optical Character Recognition (OCR) using the **full Tesseract OCR package (`tesseract-ocr-all`)**.
- Smart tagging: once you assign tags to documents, future documents are automatically tagged correctly.
- Supports GTK desktop environments.


## Installation

You can install the Snap from the Snap Store:

```bash
sudo snap install openpaperwork-snap
```

## Build your Snap Package

# Clone the repository

```bash
git clone https://github.com/Tibsun75/openpaperwork-snap.git
cd openpaperwork-snap
```
Install Snapcraft if not already installed

```bash
sudo snap install snapcraft --classic
```
Build the snap
```bash
snapcraft-v
```
The resulting snap file will be named something like:
openpaperwork-snap_2.2.5_amd64.snap



