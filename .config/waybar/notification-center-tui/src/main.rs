use std::env;
use std::process::Command;
use std::time::Duration;

use anyhow::{Context, Result};
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Cell, List, ListItem, ListState, Paragraph, Row, Table};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
struct NotificationItem {
    id: i64,
    status: String,
    preview: String,
    unread: bool,
}

#[derive(Debug, Clone, Deserialize)]
struct NotificationGroup {
    provider_label: String,
    items: Vec<NotificationItem>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Focus {
    Sections,
    Items,
}

struct AppState {
    script_path: String,
    groups: Vec<NotificationGroup>,
    section_idx: usize,
    item_idx: usize,
    focus: Focus,
}

impl AppState {
    fn new(script_path: String) -> Result<Self> {
        let mut state = Self {
            script_path,
            groups: Vec::new(),
            section_idx: 0,
            item_idx: 0,
            focus: Focus::Sections,
        };
        state.reload()?;
        Ok(state)
    }

    fn reload(&mut self) -> Result<()> {
        let cmd = format!("\"{}\" dump-json", self.script_path);
        let output = run_shell(&cmd)?;
        self.groups = serde_json::from_str(&output).context("failed to parse dump-json output")?;

        if self.section_idx >= self.groups.len() {
            self.section_idx = 0;
        }
        self.clamp_item_idx();
        Ok(())
    }

    fn clamp_item_idx(&mut self) {
        let item_count = self.current_items().len();
        if item_count == 0 {
            self.item_idx = 0;
        } else if self.item_idx >= item_count {
            self.item_idx = item_count - 1;
        }
    }

    fn current_items(&self) -> &[NotificationItem] {
        self.groups
            .get(self.section_idx)
            .map(|g| g.items.as_slice())
            .unwrap_or(&[])
    }

    fn select_next_section(&mut self) {
        if self.groups.is_empty() {
            return;
        }
        self.section_idx = (self.section_idx + 1) % self.groups.len();
        self.item_idx = 0;
        self.clamp_item_idx();
    }

    fn select_prev_section(&mut self) {
        if self.groups.is_empty() {
            return;
        }
        self.section_idx = if self.section_idx == 0 {
            self.groups.len() - 1
        } else {
            self.section_idx - 1
        };
        self.item_idx = 0;
        self.clamp_item_idx();
    }

    fn select_next_item(&mut self) {
        let items = self.current_items();
        if items.is_empty() {
            self.item_idx = 0;
            return;
        }
        self.item_idx = (self.item_idx + 1) % items.len();
    }

    fn select_prev_item(&mut self) {
        let items = self.current_items();
        if items.is_empty() {
            self.item_idx = 0;
            return;
        }
        self.item_idx = if self.item_idx == 0 {
            items.len() - 1
        } else {
            self.item_idx - 1
        };
    }

    fn open_selected(&self) -> Result<()> {
        let Some(item) = self.current_items().get(self.item_idx) else {
            return Ok(());
        };

        let cmd = format!("\"{}\" open-id {}", self.script_path, item.id);
        let _ = run_shell(&cmd)?;
        Ok(())
    }

    fn clear_unread(&mut self) -> Result<()> {
        let cmd = format!("\"{}\" clear-all", self.script_path);
        let _ = run_shell(&cmd)?;
        self.reload()?;
        Ok(())
    }
}

fn run_shell(command: &str) -> Result<String> {
    let output = Command::new("bash")
        .arg("-lc")
        .arg(command)
        .output()
        .with_context(|| format!("failed to run command: {command}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        anyhow::bail!("command failed: {command}\n{stderr}");
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn draw_ui(frame: &mut ratatui::Frame<'_>, app: &AppState) {
    let outer = Block::default()
        .title(Span::styled(
            " Notification Center ",
            Style::default().fg(Color::LightCyan).add_modifier(Modifier::BOLD),
        ))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Blue));

    let inner = outer.inner(frame.area());
    frame.render_widget(outer, frame.area());

    let main_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(1), Constraint::Length(2)])
        .split(inner);

    let body_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(34), Constraint::Percentage(66)])
        .split(main_chunks[0]);

    let section_items: Vec<ListItem> = app
        .groups
        .iter()
        .map(|g| {
            let line = Line::from(vec![
                Span::styled(&g.provider_label, Style::default().fg(Color::Magenta)),
                Span::raw(" "),
                Span::styled(
                    format!("({})", g.items.len()),
                    Style::default().fg(Color::DarkGray),
                ),
            ]);
            ListItem::new(line)
        })
        .collect();

    let mut section_state = ListState::default();
    if !app.groups.is_empty() {
        section_state.select(Some(app.section_idx));
    }

    let section_highlight = if app.focus == Focus::Sections {
        Style::default().fg(Color::Black).bg(Color::Cyan).add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)
    };

    let sections = List::new(section_items)
        .block(
            Block::default()
                .title(" Apps ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Cyan)),
        )
        .highlight_style(section_highlight)
        .highlight_symbol("▌ ");

    frame.render_stateful_widget(sections, body_chunks[0], &mut section_state);

    let item_rows: Vec<Row> = app
        .current_items()
        .iter()
        .map(|n| {
            let status_style = if n.unread {
                Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::DarkGray)
            };

            let preview_style = if n.unread {
                Style::default().fg(Color::White)
            } else {
                Style::default().fg(Color::Gray)
            };

            Row::new(vec![
                Cell::from(n.status.clone()).style(status_style),
                Cell::from(n.preview.clone()).style(preview_style),
            ])
        })
        .collect();

    let selected_group_title = app
        .groups
        .get(app.section_idx)
        .map(|g| format!(" {} ", g.provider_label))
        .unwrap_or_else(|| " Notifications ".to_string());

    let table = Table::new(
        item_rows,
        [Constraint::Length(6), Constraint::Min(20)],
    )
    .header(
        Row::new(vec![
            Cell::from("State").style(Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD)),
            Cell::from("Notification").style(Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD)),
        ])
        .style(Style::default().bg(Color::Black)),
    )
    .block(
        Block::default()
            .title(selected_group_title)
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Magenta)),
    )
    .row_highlight_style(if app.focus == Focus::Items {
        Style::default().bg(Color::Blue).fg(Color::White).add_modifier(Modifier::BOLD)
    } else {
        Style::default().bg(Color::DarkGray)
    })
    .highlight_symbol("▸ ");

    let mut table_state = ratatui::widgets::TableState::default();
    if !app.current_items().is_empty() {
        table_state.select(Some(app.item_idx));
    }
    frame.render_stateful_widget(table, body_chunks[1], &mut table_state);

    let footer = Paragraph::new(Line::from(vec![
        Span::styled("Tab", Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD)),
        Span::styled(" Switch Pane ", Style::default().fg(Color::Gray)),
        Span::styled("|", Style::default().fg(Color::DarkGray)),
        Span::styled(" Enter", Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD)),
        Span::styled(" Open App ", Style::default().fg(Color::Gray)),
        Span::styled("|", Style::default().fg(Color::DarkGray)),
        Span::styled(" c", Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD)),
        Span::styled(" Clear Unread ", Style::default().fg(Color::Gray)),
        Span::styled("|", Style::default().fg(Color::DarkGray)),
        Span::styled(" r", Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD)),
        Span::styled(" Reload ", Style::default().fg(Color::Gray)),
        Span::styled("|", Style::default().fg(Color::DarkGray)),
        Span::styled(" Esc", Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD)),
        Span::styled(" Close", Style::default().fg(Color::Gray)),
    ]));
    frame.render_widget(footer, main_chunks[1]);
}

fn main() -> Result<()> {
    let home = env::var("HOME").context("HOME is not set")?;
    let script_path = format!("{home}/.config/waybar/scripts/notification-count.sh");

    enable_raw_mode()?;
    let mut stdout = std::io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let result = run_app(&mut terminal, script_path);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

fn run_app(terminal: &mut Terminal<CrosstermBackend<std::io::Stdout>>, script_path: String) -> Result<()> {
    let mut app = AppState::new(script_path)?;

    loop {
        terminal.draw(|frame| draw_ui(frame, &app))?;

        if event::poll(Duration::from_millis(150))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }

                match key.code {
                    KeyCode::Esc | KeyCode::Char('q') => break,
                    KeyCode::Tab => {
                        app.focus = if app.focus == Focus::Sections {
                            Focus::Items
                        } else {
                            Focus::Sections
                        };
                    }
                    KeyCode::Left => app.focus = Focus::Sections,
                    KeyCode::Right => app.focus = Focus::Items,
                    KeyCode::Char('k') | KeyCode::Up => {
                        if app.focus == Focus::Sections {
                            app.select_prev_section();
                        } else {
                            app.select_prev_item();
                        }
                    }
                    KeyCode::Char('j') | KeyCode::Down => {
                        if app.focus == Focus::Sections {
                            app.select_next_section();
                        } else {
                            app.select_next_item();
                        }
                    }
                    KeyCode::Char('c') => {
                        app.clear_unread()?;
                    }
                    KeyCode::Char('r') => {
                        app.reload()?;
                    }
                    KeyCode::Enter => {
                        if app.focus == Focus::Sections {
                            app.focus = Focus::Items;
                        } else {
                            app.open_selected()?;
                            break;
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    Ok(())
}
