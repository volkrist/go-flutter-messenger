package main

import (
	"database/sql"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

func ensureSchemaMigrationsTable(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version TEXT PRIMARY KEY,
			applied_at INTEGER NOT NULL
		)
	`)
	return err
}

func getAppliedMigrations(db *sql.DB) (map[string]bool, error) {
	rows, err := db.Query(`SELECT version FROM schema_migrations`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	applied := make(map[string]bool)
	for rows.Next() {
		var version string
		if err := rows.Scan(&version); err != nil {
			return nil, err
		}
		applied[version] = true
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return applied, nil
}

func listMigrationFiles(dir string) ([]string, error) {
	var files []string

	err := filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		if strings.HasSuffix(strings.ToLower(d.Name()), ".sql") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	sort.Strings(files)
	return files, nil
}

func applyMigration(db *sql.DB, version string, sqlText string) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if strings.TrimSpace(sqlText) != "" {
		if _, err := tx.Exec(sqlText); err != nil {
			return fmt.Errorf("execute migration %s: %w", version, err)
		}
	}

	if _, err := tx.Exec(
		`INSERT INTO schema_migrations(version, applied_at) VALUES($1, $2)`,
		version,
		time.Now().Unix(),
	); err != nil {
		return fmt.Errorf("record migration %s: %w", version, err)
	}

	return tx.Commit()
}

func runMigrations(db *sql.DB, migrationsDir string) error {
	if err := ensureSchemaMigrationsTable(db); err != nil {
		return fmt.Errorf("ensure schema_migrations: %w", err)
	}

	applied, err := getAppliedMigrations(db)
	if err != nil {
		return fmt.Errorf("get applied migrations: %w", err)
	}

	files, err := listMigrationFiles(migrationsDir)
	if err != nil {
		return fmt.Errorf("list migration files: %w", err)
	}

	appliedCount := 0
	for _, path := range files {
		version := filepath.Base(path)
		if applied[version] {
			continue
		}

		content, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", version, err)
		}

		fmt.Println("Applying migration:", version)

		if err := applyMigration(db, version, string(content)); err != nil {
			return err
		}
		appliedCount++
	}

	fmt.Printf("Migrations completed, applied: %d\n", appliedCount)
	return nil
}
