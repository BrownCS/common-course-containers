# TA Course Setup Guide

Quick guide for TAs to set up courses in the CCC system.

## Required Files

Your course repo needs a `/setup` directory that houses these three files:

### 1. `/setup/packages.txt` (Course Packages)

This file holds a list of packages to be installed. It could look something like this:
```bash
inutils-doc
cpp-doc
gcc-doc
g++
g++-multilib
gdb
gdb-doc
glibc-doc
make
make-doc
clang
clang-18-doc
...
```

### 2. `setup/links.txt` (Course Symlinks)

This file holds a list of symlinks to be set. It can often be left empty! It could look like this:
```bash
/usr/bin/x86_64-linux-gnu-addr2line -> addr2line
/usr/bin/x86_64-linux-gnu-c++filt -> c++filt
/usr/bin/x86_64-linux-gnu-cpp-13 -> cpp
/usr/bin/x86_64-linux-gnu-g++-13 -> c++
/usr/bin/x86_64-linux-gnu-g++-13 -> g++
/usr/bin/x86_64-linux-gnu-gcc-13 -> gcc
/usr/bin/x86_64-linux-gnu-gcc-13 -> cc
/usr/bin/gdb-multiarch -> gdb
```

### 3. `setup/env.txt` (Course Environment Variable)\
This file holds a list of course environment variables to be loaded into the course shell. It could look like this:
```bash
TZ=America/New_York
LANG=en_US.UTF-8
CARGO_HOME=/opt/rust
RUSTUP_HOME=/opt/rust
PATH=$PATH:/opt/rust/bin
```

## Setup Steps

1. Add setup directory with 3 files above to your course dev repo
2. Add your course to the CCC registry (contact admin).

## Optional Additions

## Course-Specific Images and Installer Commands

**Default**: Most courses can use the shared Ubuntu container (write "default" nuder image_mode and leave image_ref empty)

**Course-Specific**: Courses also have the option to provide their own specific image if they desire, along with a custom installation script. CCC will not automatically run this script, however. Courses with unique containers will be run WITHOUT the CCC installer, and students must manually use the custom installation script provided by the course.

## Student Workflow

Students will:
1. `ccc open your-course` (opens the course shell with environment applied)
2. Work in assignment folders (`hw1/`, `project2/`, etc.)

## Testing

Test your setup:
```bash
# Test CCC environment loading
ccc open your-course
```

That's it! Students get a consistent environment with your customizations.
