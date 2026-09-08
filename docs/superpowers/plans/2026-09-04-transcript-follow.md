# Transcript following and reading position

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** U08/B08/B14: follow content growth until the user scrolls up, restore following on Jump to latest, and preserve reading position across resize/navigation.

**Architecture:** SessionController retains a small viewport model containing follow intent and visible row identity. Scroll phase distinguishes user scrolling from content reflow. Native scroll-position binding retains the visible row; a stable trailing sentinel anchors the actual bottom.

**Tech Stack:** SwiftUI scroll geometry/phase/position APIs, Observation, Swift Testing. API behavior checked against Apple's ScrollPhaseChangeContext and ScrollGeometry documentation.

- [ ] Add `TranscriptViewportState.swift`, retaining follow intent and row ID per controller. Content/viewport growth alone cannot unlock follow; upward user scroll does. Actual bottom arrival and Jump re-enable follow.
- [ ] Add a bottom sentinel to TranscriptView outside the padded transcript, observe size changes, and use nonanimated automatic scroll. Preserve native row position when unlocked; do not derive intent from near-bottom geometry.
- [ ] Include pending submissions and Working below the normal transcript so the actual bottom follows both before and during runtime output.
- [ ] Search navigation explicitly disables follow and reveals the selected row; Jump clears search positioning and returns to bottom.
- [ ] Regression checks distinguish content growth from user upward movement, bottom arrival, jump, and a retained per-controller anchor. Verify real Release streaming, resize with an expanded tool, session switches, and Reduce Motion. Capture evidence for both locked and unlocked states.
