//
//  PresentationTests.swift
//  AskcalTests
//
//  The small pure functions behind what things are called and how a day is
//  summarised. Each is here because getting it wrong is silent: a theme that
//  resets itself, a summary that reports zero for the thing it exists to count,
//  a note whose preview shows a markdown hash instead of a sentence.
//

import Foundation
import Testing

@testable import Askcal

// MARK: - Naming a track nobody has fetched yet

struct TrackNamingTests {

    @Test func aSlugBecomesAReadableTitle() {
        // Used for mail filed under a track that has since been deleted, or
        // before the track list has arrived.
        #expect(Track.title(for: "side-projects") == "Side Projects")
        #expect(Track.title(for: "uni") == "Uni")
    }

    @Test func theBuiltInsKeepTheirSymbols() {
        #expect(Track.icon(for: "uni") == "graduationcap")
        #expect(Track.icon(for: "finance") == "creditcard")
    }

    @Test func aTrackTheUserInventedGetsANeutralSymbol() {
        // Guessing a symbol from a name someone chose is a worse failure than
        // not trying.
        #expect(Track.icon(for: "side-projects") == "bookmark")
    }

    @Test func aTrackWithNoLabelFallsBackToItsSlug() throws {
        let json = Data(#"{"id":"side-projects"}"#.utf8)
        let decoded = try APIDates.decoder.decode(Track.self, from: json)

        #expect(decoded.label == "Side Projects")
        #expect(decoded.active)
    }
}

// MARK: - Naming a mailbox

struct MailboxNamingTests {

    private func account(label: String?) -> MailAccount {
        MailAccount(
            id: UUID(), email: "snafees.cs23@bmsce.ac.in", label: label,
            isPrimary: false, active: true, connected: true
        )
    }

    @Test func theUsersOwnNameWins() {
        #expect(account(label: "college").title == "college")
    }

    @Test func withNoNameItUsesThePartBeforeTheAt() {
        // The full address was the row's title once: long, wrapping, and the
        // one fact the reader already knows.
        #expect(account(label: nil).title == "snafees.cs23")
    }

    @Test func anEmptyNameIsNotAName() {
        #expect(account(label: "").title == "snafees.cs23")
    }
}

// MARK: - The day's page

struct DayNoteTests {

    private func note(_ body: String) -> DayNote {
        DayNote(day: .now, body: body, updatedAt: nil)
    }

    @Test func aHeadingReadsAsASentenceInThePreview() {
        // The collapsed row on the phone shows one line. "# standup" there is a
        // hash and a word, not a title.
        #expect(note("# standup\nask about staging").summary == "standup")
    }

    @Test func bulletsAndQuotesAreStrippedToo() {
        #expect(note("- call the bank").summary == "call the bank")
        #expect(note("> they said friday").summary == "they said friday")
    }

    @Test func leadingBlankLinesAreSkipped() {
        #expect(note("\n\n  actual first line").summary == "actual first line")
    }

    @Test func whitespaceOnlyIsEmpty() {
        #expect(note("   \n\n ").isEmpty)
        #expect(!note("x").isEmpty)
    }
}

// MARK: - What the day came to

@MainActor
struct ReviewSummaryTests {

    private func store(done: Int, carried: Int) -> AskcalStore {
        let store = AskcalStore()
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)

        store.tasks =
            (0..<done).map {
                AskcalTask(
                    id: UUID(), track: "uni", title: "done \($0)", regretScore: 10,
                    status: .done, scheduledFor: today, completedAt: .now
                )
            }
            + (0..<carried).map {
                AskcalTask(
                    id: UUID(), track: "uni", title: "moved \($0)", regretScore: 10,
                    status: .carried, scheduledFor: tomorrow
                )
            }
        return store
    }

    @Test func itCountsWhatWasFinishedAndWhatMoved() {
        #expect(store(done: 3, carried: 1).reviewSummary == "3 done · 1 moved to tomorrow")
    }

    @Test func oneMovedTaskIsNotPluralised() {
        #expect(store(done: 0, carried: 1).reviewSummary.contains("1 moved to tomorrow"))
    }

    @Test func carriedWorkStillCountsAfterItHasMovedToTomorrow() {
        // The summary said "0 moved to tomorrow" for a day whose whole point was
        // what got moved: carrying files a task on tomorrow immediately, and the
        // day list only holds today.
        let store = store(done: 0, carried: 2)
        #expect(store.dayEntries.isEmpty)
        #expect(store.reviewSummary.contains("2 moved"))
    }
}

// MARK: - Remembering the theme

struct ThemeStorageTests {

    @Test func everyLegacyNameStillResolves() {
        // Four names have been stored over this app's life. A miss here does not
        // error — it silently resets the theme on every existing install.
        #expect(ThemeMode.stored("light") == .day)
        #expect(ThemeMode.stored("paper") == .day)
        #expect(ThemeMode.stored("dark") == .night)
        #expect(ThemeMode.stored("slate") == .night)
    }

    @Test func theCurrentNamesResolveToThemselves() {
        #expect(ThemeMode.stored("day") == .day)
        #expect(ThemeMode.stored("night") == .night)
    }

    @Test func somethingUnrecognisedFallsBackRatherThanCrashing() {
        #expect(ThemeMode.stored("chartreuse") == ThemeMode.stored(ThemeMode.storageDefault))
    }
}
