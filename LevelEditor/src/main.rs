use std::{
    fs,
    ops::RangeInclusive,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, anyhow};
use eframe::egui::{self, Align2, Color32, DragValue, FontId, Painter, Pos2, Shape, Stroke, Vec2};
use serde::{Deserialize, Serialize};
use serde_json::Value;

const AUX_LABEL_FONT: f32 = 11.0;
const FORMATION_ROW_SIZE: usize = 6;
const HUD_HALF_WIDTH: f32 = 640.0;
const HUD_HALF_HEIGHT: f32 = 480.0;
const HUD_OVERSCAN: f32 = 80.0;
const ROW_COLORS: [Color32; 6] = [
    Color32::from_rgb(255, 140, 66),
    Color32::from_rgb(255, 216, 90),
    Color32::from_rgb(140, 209, 102),
    Color32::from_rgb(88, 191, 255),
    Color32::from_rgb(202, 138, 255),
    Color32::from_rgb(255, 113, 164),
];

#[derive(Default)]
struct CanvasResult {
    selection: Option<usize>,
    changed: bool,
}

fn main() -> eframe::Result<()> {
    let initial_path = std::env::args().nth(1).map(PathBuf::from);
    let options = eframe::NativeOptions::default();
    eframe::run_native(
        "Warblade Level Editor",
        options,
        Box::new(|_cc| Box::new(LevelEditorApp::new(initial_path))),
    )
}

struct LevelEditorApp {
    path_input: String,
    descriptor: Option<DescriptorRoot>,
    descriptor_path: Option<PathBuf>,
    raw_json: Option<Value>,
    load_error: Option<String>,
    save_status: Option<SaveStatus>,
    dirty: bool,
    save_copy_path_input: String,
    selected_index: usize,
    selected_wave_index: usize,
    selected_aux_index: usize,
    view_mode: ViewMode,
    formation_canvas_mode: FormationCanvasMode,
    aux_playback: AuxPlaybackState,
    formation_playback: FormationPlaybackState,
    formation_drag: FormationDragState,
    wave_gesture: WaveGestureState,
    wave_mode: WaveEditMode,
    aux_drag: AuxDragState,
    help_visible: bool,
}

enum SaveStatus {
    Success(String),
    Error(String),
}

impl LevelEditorApp {
    fn new(initial_path: Option<PathBuf>) -> Self {
        let mut app = Self {
            path_input: initial_path
                .as_ref()
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_default(),
            descriptor: None,
            descriptor_path: None,
            raw_json: None,
            load_error: None,
            save_status: None,
            dirty: false,
            save_copy_path_input: initial_path
                .as_ref()
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_default(),
            selected_index: 0,
            selected_wave_index: 0,
            selected_aux_index: 0,
            view_mode: ViewMode::Formations,
            formation_canvas_mode: FormationCanvasMode::HudOffsets,
            aux_playback: AuxPlaybackState::default(),
            formation_playback: FormationPlaybackState::default(),
            formation_drag: FormationDragState::default(),
            wave_gesture: WaveGestureState::default(),
            wave_mode: WaveEditMode::Points,
            aux_drag: AuxDragState::default(),
            help_visible: false,
        };
        if let Some(path) = initial_path {
            if let Err(err) = app.load_from_path(&path) {
                app.load_error = Some(err.to_string());
            }
        }
        app
    }

    fn try_load_from_input(&mut self) {
        let trimmed = self.path_input.trim();
        if trimmed.is_empty() {
            self.load_error = Some("Enter a JSON descriptor path first.".into());
            return;
        }
        let path = PathBuf::from(trimmed);
        match self.load_from_path(&path) {
            Ok(()) => self.load_error = None,
            Err(err) => self.load_error = Some(err.to_string()),
        }
    }

    fn load_from_path(&mut self, path: &PathBuf) -> Result<()> {
        let data = fs::read_to_string(path)
            .with_context(|| format!("Unable to read {}", path.display()))?;
        let raw_json: Value = serde_json::from_str(&data)
            .with_context(|| format!("Invalid descriptor JSON in {}", path.display()))?;
        let descriptor: DescriptorRoot = serde_json::from_value(raw_json.clone())
            .with_context(|| format!("Descriptor schema mismatch in {}", path.display()))?;
        if descriptor
            .sections
            .enemy_formations
            .as_ref()
            .map(|section| section.records.is_empty())
            .unwrap_or(true)
        {
            return Err(anyhow!(
                "Descriptor lacks populated enemy_formations records, cannot visualize formations."
            ));
        }
        self.selected_index = 0;
        self.selected_wave_index = 0;
        self.selected_aux_index = 0;
        self.descriptor_path = Some(path.clone());
        self.descriptor = Some(descriptor);
        self.raw_json = Some(raw_json);
        self.reset_playback_state();
        self.formation_playback.reset();
        self.formation_drag.clear();
        self.wave_gesture.clear();
        self.wave_mode = WaveEditMode::Points;
        self.aux_drag.clear();
        self.path_input = path.to_string_lossy().into_owned();
        self.save_copy_path_input = self.path_input.clone();
        self.save_status = None;
        self.dirty = false;
        if let ViewMode::Aux(kind) = self.view_mode {
            if self
                .descriptor
                .as_ref()
                .and_then(|d| d.sections.get_aux(kind))
                .is_none()
            {
                self.view_mode = ViewMode::Formations;
            }
        }
        Ok(())
    }

    fn reset_playback_state(&mut self) {
        self.aux_playback.reset();
    }

    fn ensure_wave_selection(&mut self, section: &FormationSection) {
        if section.records.is_empty() {
            self.selected_index = 0;
            self.selected_wave_index = 0;
            return;
        }
        let max_index = section.records.len() - 1;
        if self.selected_index > max_index {
            self.selected_index = max_index;
        }
        let inferred_wave = self.selected_index / FORMATION_ROW_SIZE;
        let max_wave = wave_count(section).saturating_sub(1);
        self.selected_wave_index = self.selected_wave_index.min(max_wave);
        if inferred_wave != self.selected_wave_index {
            self.selected_wave_index = inferred_wave.min(max_wave);
        }
    }

    fn set_selected_wave(&mut self, section: &FormationSection, wave_index: usize) {
        if section.records.is_empty() {
            self.selected_wave_index = 0;
            self.selected_index = 0;
            return;
        }
        let max_wave = wave_count(section).saturating_sub(1);
        let clamped_wave = wave_index.min(max_wave);
        self.selected_wave_index = clamped_wave;
        let start = clamped_wave * FORMATION_ROW_SIZE;
        let max_index = section.records.len().saturating_sub(1);
        self.selected_index = start.min(max_index);
        self.formation_drag.clear();
        self.wave_gesture.clear();
    }

    fn set_selected_record(&mut self, section: &FormationSection, record_index: usize) {
        if section.records.is_empty() {
            self.selected_index = 0;
            self.selected_wave_index = 0;
            return;
        }
        let max_index = section.records.len() - 1;
        self.selected_index = record_index.min(max_index);
        self.selected_wave_index = self.selected_index / FORMATION_ROW_SIZE;
        self.formation_drag.clear();
        self.wave_gesture.clear();
    }

    fn mark_dirty(&mut self) {
        if !self.dirty {
            self.dirty = true;
        }
        self.save_status = None;
    }

    fn save_descriptor_to(&mut self, destination: &Path, update_loaded_path: bool) -> Result<()> {
        let descriptor = self
            .descriptor
            .as_mut()
            .ok_or_else(|| anyhow!("No descriptor loaded"))?;
        descriptor.refresh_metadata();
        let mut raw = self
            .raw_json
            .clone()
            .ok_or_else(|| anyhow!("Original JSON tree unavailable"))?;

        if let Some(section) = descriptor.sections.enemy_formations.as_ref() {
            write_section_value(&mut raw, "enemy_formations", section)?;
        }
        if let Some(section) = descriptor.sections.promotion_banner_paths.as_ref() {
            write_section_value(&mut raw, "promotion_banner_paths", section)?;
        }
        if let Some(section) = descriptor.sections.meteor_arc_paths.as_ref() {
            write_section_value(&mut raw, "meteor_arc_paths", section)?;
        }
        if let Some(section) = descriptor.sections.boss_callout_paths.as_ref() {
            write_section_value(&mut raw, "boss_callout_paths", section)?;
        }
        if let Some(section) = descriptor.sections.rank_marker_gates.as_ref() {
            write_section_value(&mut raw, "rank_marker_gates", section)?;
        }
        if let Some(section) = descriptor.sections.reward_ribbon_paths.as_ref() {
            write_section_value(&mut raw, "reward_ribbon_paths", section)?;
        }
        if let Some(section) = descriptor.sections.hud_flash_counters.as_ref() {
            write_section_value(&mut raw, "hud_flash_counters", section)?;
        }
        if let Some(section) = descriptor.sections.news_ticker_globals.as_ref() {
            write_section_value(&mut raw, "news_ticker_globals", section)?;
        }

        let serialized = serde_json::to_string_pretty(&raw)?;
        fs::write(destination, serialized)
            .with_context(|| format!("Failed to write {}", destination.display()))?;

        if update_loaded_path {
            self.descriptor_path = Some(destination.to_path_buf());
            self.path_input = destination.to_string_lossy().into_owned();
            self.raw_json = Some(raw);
            self.dirty = false;
        }

        Ok(())
    }

    fn formation_section(&self) -> Option<&FormationSection> {
        self.descriptor
            .as_ref()
            .and_then(|desc| desc.sections.enemy_formations.as_ref())
    }

    fn available_aux_sections(&self) -> Vec<AuxSectionKind> {
        let mut kinds = Vec::new();
        if let Some(desc) = &self.descriptor {
            for kind in AuxSectionKind::ALL {
                if desc.sections.get_aux(*kind).is_some() {
                    kinds.push(*kind);
                }
            }
        }
        kinds
    }

    fn render_wave_editor(
        &mut self,
        ui: &mut egui::Ui,
        section: &mut FormationSection,
        canvas_mode: FormationCanvasMode,
        playhead: Option<f32>,
    ) -> bool {
        self.ensure_wave_selection(section);
        let mut dirty = false;
        ui.heading("Wave & Path Editor");
        ui.label(
            "Shape enemy waves with spline-like handles, then fine-tune individual slots below.",
        );
        ui.label("Use the toolbar to add or clone waves, then switch between point editing, move, rotate, or zoom modes.");
        ui.separator();

        dirty |= self.render_wave_toolbar(ui, section);

        ui.separator();

        let mut canvas_dirty = false;
        if !section.records.is_empty() {
            let canvas_result = match canvas_mode {
                FormationCanvasMode::HudOffsets => draw_wave_path_canvas(
                    ui,
                    &mut section.records,
                    self.selected_index,
                    self.selected_wave_index,
                    self.wave_mode,
                    &mut self.formation_drag,
                    &mut self.wave_gesture,
                ),
                FormationCanvasMode::SpawnTimeline => {
                    draw_timeline_canvas(ui, &section.records, self.selected_index, playhead)
                }
            };
            if let Some(idx) = canvas_result.selection {
                self.set_selected_record(section, idx);
            }
            if canvas_result.changed {
                canvas_dirty = true;
            }
            ui.separator();
        } else {
            ui.label("Descriptor has no formations to edit.");
        }

        dirty |= canvas_dirty;

        ui.columns(2, |columns| {
            self.render_wave_list_panel(&mut columns[0], section);
            dirty |= self.render_wave_slots_panel(&mut columns[1], section);
        });

        ui.separator();

        egui::CollapsingHeader::new("All formation records (raw)")
            .default_open(false)
            .show(ui, |ui| {
                self.render_full_record_grid(ui, section);
            });

        dirty
    }

    fn render_wave_toolbar(&mut self, ui: &mut egui::Ui, section: &mut FormationSection) -> bool {
        let mut dirty = false;
        ui.horizontal(|ui| {
            for label in ["LEVELS", "LEVEL PACK", "ALIENS", "MORE"] {
                ui.add_enabled(false, egui::Button::new(label));
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("HELP").clicked() {
                    self.help_visible = true;
                }
            });
        });
        ui.horizontal(|ui| {
            if ui.button("Add Wave").clicked() {
                let new_wave = section.add_wave();
                self.set_selected_wave(section, new_wave);
                dirty = true;
            }
            let can_clone = wave_range(section, self.selected_wave_index).is_some();
            if ui
                .add_enabled(can_clone, egui::Button::new("Clone"))
                .clicked()
            {
                if let Some(new_wave) = section.clone_wave(self.selected_wave_index) {
                    self.set_selected_wave(section, new_wave);
                    dirty = true;
                }
            }
            if ui
                .add_enabled(can_clone, egui::Button::new("Clone X"))
                .clicked()
            {
                if let Some(new_wave) =
                    section.clone_wave_mirrored(self.selected_wave_index, MirrorAxis::Horizontal)
                {
                    self.set_selected_wave(section, new_wave);
                    dirty = true;
                }
            }
            if ui
                .add_enabled(can_clone, egui::Button::new("Clone Y"))
                .clicked()
            {
                if let Some(new_wave) =
                    section.clone_wave_mirrored(self.selected_wave_index, MirrorAxis::Vertical)
                {
                    self.set_selected_wave(section, new_wave);
                    dirty = true;
                }
            }
            if ui
                .add_enabled(wave_count(section) > 1, egui::Button::new("Delete Wave"))
                .clicked()
            {
                if section.remove_wave(self.selected_wave_index) {
                    let new_wave = self.selected_wave_index.saturating_sub(1);
                    self.set_selected_wave(section, new_wave);
                    dirty = true;
                }
            }
        });

        if let Some(wave_slice) = wave_slice_mut(&mut section.records, self.selected_wave_index) {
            egui::Grid::new("wave_props").striped(true).show(ui, |ui| {
                dirty |= wave_param_row(
                    ui,
                    "Wave Wait (spawn start)",
                    wave_slice,
                    |rec| rec.spawn_delay_start,
                    |rec, val| rec.spawn_delay_start = val,
                    -100_000..=100_000,
                );
                dirty |= wave_param_row(
                    ui,
                    "Alien Wait (secondary delay)",
                    wave_slice,
                    |rec| rec.spawn_delay_secondary,
                    |rec, val| rec.spawn_delay_secondary = val,
                    -100_000..=100_000,
                );
                dirty |= wave_param_row(
                    ui,
                    "Level Window",
                    wave_slice,
                    |rec| rec.spawn_window_secondary,
                    |rec, val| rec.spawn_window_secondary = val,
                    -100_000..=100_000,
                );
                dirty |= wave_param_row(
                    ui,
                    "Acceleration (increment)",
                    wave_slice,
                    |rec| rec.spawn_delay_increment,
                    |rec, val| rec.spawn_delay_increment = val,
                    -10_000..=10_000,
                );
            });
        }

        ui.horizontal(|ui| {
            for mode in [
                WaveEditMode::Points,
                WaveEditMode::Move,
                WaveEditMode::Scale,
                WaveEditMode::Rotate,
            ] {
                let button = egui::Button::new(mode.label()).min_size(Vec2::new(80.0, 32.0));
                if ui.add(button).clicked() {
                    self.wave_mode = mode;
                    self.wave_gesture.clear();
                    self.formation_drag.clear();
                }
            }
            if ui.button("Delete Slot").clicked() {
                if let Some(record) = section.records.get_mut(self.selected_index) {
                    *record = FormationRecord::default();
                    dirty = true;
                }
            }
        });

        dirty
    }

    fn render_wave_list_panel(&mut self, ui: &mut egui::Ui, section: &FormationSection) {
        let total = wave_count(section);
        ui.heading("Waves");
        ui.label(format!("{} total", total));
        egui::ScrollArea::vertical()
            .id_source("wave_list")
            .max_height(220.0)
            .show(ui, |ui| {
                for wave_idx in 0..total {
                    let label = format!("Wave {:03}", wave_idx);
                    let summary = wave_range(section, wave_idx)
                        .map(|(start, end)| {
                            let active = section.records[start..end]
                                .iter()
                                .filter(|rec| rec.enemy_type != 0)
                                .count();
                            format!("{label} · {} slots", active)
                        })
                        .unwrap_or(label.clone());
                    let selected = wave_idx == self.selected_wave_index;
                    if ui.selectable_label(selected, summary).clicked() {
                        self.set_selected_wave(section, wave_idx);
                    }
                }
            });
    }

    fn render_wave_slots_panel(
        &mut self,
        ui: &mut egui::Ui,
        section: &mut FormationSection,
    ) -> bool {
        let mut dirty = false;
        let Some((start, end)) = wave_range(section, self.selected_wave_index) else {
            ui.label("No wave selected");
            return false;
        };
        ui.heading(format!("Wave {:03} slots", self.selected_wave_index));
        egui::Grid::new("wave_slot_grid")
            .striped(true)
            .show(ui, |ui| {
                ui.strong("Slot");
                ui.strong("Spawn");
                ui.strong("Offsets");
                ui.strong("Enemy");
                ui.strong("Behavior");
                ui.end_row();
                for idx in start..end {
                    if let Some(record) = section.records.get(idx) {
                        let selected = idx == self.selected_index;
                        let slot_label = format!("{}", idx - start);
                        if ui.selectable_label(selected, slot_label).clicked() {
                            self.set_selected_record(section, idx);
                        }
                        ui.label(format!(
                            "{} / {}",
                            record.spawn_delay_start, record.spawn_delay_secondary
                        ));
                        ui.label(format!("{}, {}", record.offset_x, record.offset_y));
                        ui.label(record.enemy_type.to_string());
                        ui.label(format!("{:#x}", record.behavior_flags));
                        ui.end_row();
                    }
                }
            });

        ui.separator();
        if let Some(record) = section.records.get_mut(self.selected_index) {
            ui.heading(format!("Slot {} details", self.selected_index - start));
            egui::Grid::new("wave_slot_details").show(ui, |ui| {
                dirty |= drag_i32_row(
                    ui,
                    "Spawn Delay Start",
                    &mut record.spawn_delay_start,
                    -100_000..=100_000,
                );
                dirty |= drag_i32_row(
                    ui,
                    "Spawn Delay Increment",
                    &mut record.spawn_delay_increment,
                    -10_000..=10_000,
                );
                dirty |= drag_i32_row(
                    ui,
                    "Spawn Delay Secondary",
                    &mut record.spawn_delay_secondary,
                    -100_000..=100_000,
                );
                dirty |= drag_i32_row(
                    ui,
                    "Spawn Window Secondary",
                    &mut record.spawn_window_secondary,
                    -100_000..=100_000,
                );
                dirty |= drag_i32_row(ui, "Offset X", &mut record.offset_x, -1_000..=1_000);
                dirty |= drag_i32_row(ui, "Offset Y", &mut record.offset_y, -1_000..=1_000);
                dirty |= drag_i32_row(ui, "Enemy Type", &mut record.enemy_type, 0..=255);
                dirty |= drag_i32_row(
                    ui,
                    "Behavior Flags",
                    &mut record.behavior_flags,
                    -10_000..=10_000,
                );
            });
            ui.separator();
            dirty |= render_point_command_panel(ui, record);
        }

        dirty
    }

    fn render_full_record_grid(&mut self, ui: &mut egui::Ui, section: &FormationSection) {
        egui::ScrollArea::vertical()
            .id_source("formation_scroll_full")
            .show(ui, |ui| {
                egui::Grid::new("formation_grid_full")
                    .striped(true)
                    .min_col_width(80.0)
                    .show(ui, |ui| {
                        ui.strong("Idx");
                        ui.strong("Row");
                        ui.strong("Spawn Delay");
                        ui.strong("Offset X");
                        ui.strong("Offset Y");
                        ui.strong("Enemy Type");
                        ui.strong("Behavior");
                        ui.end_row();
                        for (idx, record) in section.records.iter().enumerate() {
                            let selected = self.selected_index == idx;
                            let resp = ui.selectable_label(selected, idx.to_string());
                            if resp.clicked() {
                                self.set_selected_record(section, idx);
                            }
                            ui.label(format!("Row {}", idx / FORMATION_ROW_SIZE));
                            ui.label(format!(
                                "{} / {}",
                                record.spawn_delay_start, record.spawn_delay_secondary
                            ));
                            ui.label(record.offset_x.to_string());
                            ui.label(record.offset_y.to_string());
                            ui.label(record.enemy_type.to_string());
                            ui.label(format!("{:#x}", record.behavior_flags));
                            ui.end_row();
                        }
                    });
            });
    }
}

fn render_point_command_panel(ui: &mut egui::Ui, record: &mut FormationRecord) -> bool {
    let mut dirty = false;
    ui.group(|ui| {
        ui.label("Point Command");
        ui.horizontal(|ui| {
            if ui.button("<<").clicked() {
                record.behavior_flags = record.behavior_flags.saturating_sub(1);
                dirty = true;
            }
            if ui.button(">>").clicked() {
                record.behavior_flags = record.behavior_flags.saturating_add(1);
                dirty = true;
            }
            ui.label(format!("Command #{:#06x}", record.behavior_flags));
        });
        ui.horizontal(|ui| {
            ui.label("Parameter 1 (Enemy Type)");
            let mut value = record.enemy_type;
            if ui
                .add(DragValue::new(&mut value).clamp_range(0..=255))
                .changed()
            {
                record.enemy_type = value;
                dirty = true;
            }
        });
        ui.horizontal(|ui| {
            ui.label("Parameter 2 (Delay Increment)");
            let mut value = record.spawn_delay_increment;
            if ui
                .add(DragValue::new(&mut value).clamp_range(-10_000..=10_000))
                .changed()
            {
                record.spawn_delay_increment = value;
                dirty = true;
            }
        });
        ui.horizontal(|ui| {
            ui.label("Level Limit (Respawn Window)");
            let mut value = record.spawn_window_secondary;
            if ui
                .add(DragValue::new(&mut value).clamp_range(-100_000..=100_000))
                .changed()
            {
                record.spawn_window_secondary = value;
                dirty = true;
            }
        });
        ui.small("These controls map directly to the behavior flags and timing fields stored in the descriptor, so edits round-trip with the JSON.");
    });
    dirty
}

impl eframe::App for LevelEditorApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::SidePanel::left("descriptor_panel")
            .resizable(true)
            .default_width(260.0)
            .show(ctx, |ui| {
                ui.heading("Descriptor");
                ui.label("JSON Path");
                ui.add(
                    egui::TextEdit::singleline(&mut self.path_input)
                        .hint_text("reports/classic_level_001.json"),
                );
                if ui.button("Load JSON").clicked() {
                    self.try_load_from_input();
                }
                if let Some(path) = &self.descriptor_path {
                    ui.label(format!("Loaded: {}", path.display()));
                }
                if let Some(err) = &self.load_error {
                    ui.colored_label(Color32::RED, err);
                }
                if self.descriptor.is_some() {
                    if self.dirty {
                        ui.colored_label(Color32::YELLOW, "Unsaved changes");
                    }
                    if let Some(status) = &self.save_status {
                        match status {
                            SaveStatus::Success(msg) => {
                                ui.colored_label(Color32::LIGHT_GREEN, msg);
                            }
                            SaveStatus::Error(msg) => {
                                ui.colored_label(Color32::RED, msg);
                            }
                        }
                    }
                    let can_save = self.dirty && self.descriptor_path.is_some();
                    ui.horizontal(|ui| {
                        if ui
                            .add_enabled(can_save, egui::Button::new("Save"))
                            .clicked()
                        {
                            if let Some(path) = self.descriptor_path.clone() {
                                match self.save_descriptor_to(path.as_path(), true) {
                                    Ok(()) => {
                                        self.save_status = Some(SaveStatus::Success(format!(
                                            "Saved {}",
                                            path.display()
                                        )));
                                    }
                                    Err(err) => {
                                        self.save_status = Some(SaveStatus::Error(err.to_string()));
                                    }
                                }
                            }
                        }
                        if ui.button("Save Copy").clicked() {
                            let trimmed = self.save_copy_path_input.trim();
                            if trimmed.is_empty() {
                                self.save_status = Some(SaveStatus::Error(
                                    "Enter a path for the copy first.".into(),
                                ));
                            } else {
                                let copy_path = PathBuf::from(trimmed);
                                match self.save_descriptor_to(copy_path.as_path(), false) {
                                    Ok(()) => {
                                        self.save_status = Some(SaveStatus::Success(format!(
                                            "Wrote copy to {}",
                                            copy_path.display()
                                        )));
                                    }
                                    Err(err) => {
                                        self.save_status = Some(SaveStatus::Error(err.to_string()));
                                    }
                                }
                            }
                        }
                    });
                    ui.add(
                        egui::TextEdit::singleline(&mut self.save_copy_path_input)
                            .hint_text("reports/classic_level_001.edited.json"),
                    );
                }
                let mut view_changed = false;
                let aux_options = self.available_aux_sections();
                egui::ComboBox::from_label("Preview Mode")
                    .selected_text(self.view_mode.label())
                    .show_ui(ui, |ui| {
                        view_changed |= ui
                            .selectable_value(
                                &mut self.view_mode,
                                ViewMode::Formations,
                                "Enemy Formations",
                            )
                            .changed();
                        for kind in &aux_options {
                            view_changed |= ui
                                .selectable_value(
                                    &mut self.view_mode,
                                    ViewMode::Aux(*kind),
                                    kind.display_name(),
                                )
                                .changed();
                        }
                    });
                if view_changed {
                    self.selected_index = 0;
                    self.selected_wave_index = 0;
                    self.selected_aux_index = 0;
                    self.wave_gesture.clear();
                }
                if matches!(self.view_mode, ViewMode::Formations) {
                    ui.horizontal(|ui| {
                        ui.label("Formation View");
                        ui.selectable_value(
                            &mut self.formation_canvas_mode,
                            FormationCanvasMode::HudOffsets,
                            "HUD offsets",
                        );
                        ui.selectable_value(
                            &mut self.formation_canvas_mode,
                            FormationCanvasMode::SpawnTimeline,
                            "Spawn timeline",
                        );
                    });
                }

                if let Some(section) = self.formation_section() {
                    ui.separator();
                    ui.label(format!(
                        "Enemy formations: {} records (blocks {}-{})",
                        section.record_count, section.start_block, section.end_block
                    ));
                } else {
                    ui.separator();
                    ui.label("Load a descriptor to inspect formations.");
                }
            });

        egui::CentralPanel::default().show(ctx, |ui| match self.view_mode {
            ViewMode::Formations => {
                let canvas_mode = self.formation_canvas_mode;
                let mut dirty_after_section = false;
                if let Some(mut desc) = self.descriptor.take() {
                    if let Some(section_meta) = desc.sections.enemy_formations.as_ref() {
                        let duration = formation_total_duration(section_meta);
                        advance_formation_playback_state(
                            &mut self.formation_playback,
                            ui.ctx(),
                            duration,
                        );
                        if duration > 0.0 {
                            render_formation_playback_controls(
                                &mut self.formation_playback,
                                ui,
                                duration,
                            );
                            ui.separator();
                        }
                    } else {
                        self.formation_playback.reset();
                    }

                    if let Some(section) = desc.sections.enemy_formations.as_mut() {
                        let playhead = if section.records.is_empty() {
                            None
                        } else {
                            Some(self.formation_playback.playhead)
                        };
                        if self.render_wave_editor(ui, section, canvas_mode, playhead) {
                            dirty_after_section = true;
                        }
                    } else {
                        ui.centered_and_justified(|ui| {
                            ui.label("Selected descriptor lacks enemy formations.");
                        });
                    }

                    self.descriptor = Some(desc);
                } else {
                    ui.centered_and_justified(|ui| {
                        ui.label("Load a Warblade descriptor JSON to view formations.");
                    });
                }
                if dirty_after_section {
                    self.mark_dirty();
                }
            }
            ViewMode::Aux(kind) => {
                self.render_aux_section(ui, kind);
            }
        });

        if self.help_visible {
            egui::Window::new("Wave Editor Help")
                .open(&mut self.help_visible)
                .collapsible(false)
                .resizable(false)
                .show(ctx, |ui| {
                    ui.label("Shortcuts & gestures");
                    ui.separator();
                    ui.label("• POINTS mode: drag individual slots to reposition them inside the HUD frame.");
                    ui.label("• MOVE mode: drag anywhere on the canvas to slide the entire wave.");
                    ui.label("• ROTATE mode: drag to rotate around the wave centroid (shown as the highlighted start point).");
                    ui.label("• ZOOM mode: drag away/toward the centroid to scale the wave uniformly.");
                    ui.label("• Delete Slot resets the highlighted slot to zero offsets without affecting neighbors.");
                    ui.label("• Use the arrows next to Point Command to step behavior flags or type exact values in the field below.");
                    ui.separator();
                    ui.small("All edits update the loaded descriptor immediately; Save/Save Copy writes the JSON back to disk.");
                });
        }
    }
}

fn draw_wave_path_canvas(
    ui: &mut egui::Ui,
    records: &mut [FormationRecord],
    selected_index: usize,
    selected_wave: usize,
    mode: WaveEditMode,
    drag_state: &mut FormationDragState,
    gesture_state: &mut WaveGestureState,
) -> CanvasResult {
    let mut result = CanvasResult::default();
    let Some((start, end)) = wave_range_from_records(records, selected_wave) else {
        ui.label("No wave data available.");
        gesture_state.clear();
        drag_state.clear();
        return result;
    };

    let width = ui.available_width().max(320.0);
    let height = 400.0;
    let (rect, response) =
        ui.allocate_exact_size(Vec2::new(width, height), egui::Sense::click_and_drag());
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 4.0, Color32::from_rgb(10, 12, 14));
    painter.rect_stroke(rect, 4.0, Stroke::new(1.0, Color32::from_gray(70)));

    let min_x = -HUD_HALF_WIDTH - HUD_OVERSCAN;
    let max_x = HUD_HALF_WIDTH + HUD_OVERSCAN;
    let min_y = -HUD_HALF_HEIGHT - HUD_OVERSCAN;
    let max_y = HUD_HALF_HEIGHT + HUD_OVERSCAN;
    let usable_w = (rect.width() - 48.0).max(1.0);
    let usable_h = (rect.height() - 48.0).max(1.0);
    let scale_x = usable_w / (max_x - min_x);
    let scale_y = usable_h / (max_y - min_y);
    let transform = CanvasTransform::new(rect, 24.0, min_x, min_y, scale_x, scale_y);

    let play_area_top_left = transform.project(-HUD_HALF_WIDTH, HUD_HALF_HEIGHT);
    let play_area_bottom_right = transform.project(HUD_HALF_WIDTH, -HUD_HALF_HEIGHT);
    let mut play_rect = egui::Rect::from_two_pos(play_area_top_left, play_area_bottom_right);
    play_rect = play_rect.shrink(1.0);
    painter.rect_stroke(
        play_rect,
        2.0,
        Stroke::new(2.0, Color32::from_rgb(178, 58, 58)),
    );

    let points: Vec<(usize, Pos2, (f32, f32))> = (start..end)
        .filter_map(|idx| {
            records.get(idx).map(|rec| {
                let world = (rec.offset_x as f32, rec.offset_y as f32);
                let pos = transform.project(world.0, world.1);
                (idx, pos, world)
            })
        })
        .collect();

    if points.len() >= 2 {
        let polyline: Vec<Pos2> = points.iter().map(|(_, pos, _)| *pos).collect();
        painter.add(Shape::line(
            polyline,
            Stroke::new(2.0, Color32::from_rgb(92, 198, 255)),
        ));
    }

    let mut hovered_idx: Option<usize> = None;
    if let Some(pos) = response.hover_pos() {
        hovered_idx = points
            .iter()
            .map(|(idx, p, _)| (*idx, p.distance(pos)))
            .min_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .and_then(|(idx, dist)| if dist < 18.0 { Some(idx) } else { None });
        if hovered_idx.is_some() {
            painter.circle_stroke(pos, 8.0, Stroke::new(1.5, Color32::from_gray(180)));
        }
    }

    if !matches!(mode, WaveEditMode::Points) {
        drag_state.clear();
    }

    let pointer_pos = response.interact_pointer_pos();
    let mut new_selection: Option<usize> = None;
    let mut clear_drag = false;

    if matches!(mode, WaveEditMode::Points) {
        if let Some(active) = drag_state.active.as_mut() {
            if let Some(pos) = pointer_pos {
                if let Some(record) = records.get_mut(active.record_index) {
                    let (world_x, world_y) = transform.unproject(pos);
                    let new_x = world_x - active.grab_delta.0;
                    let new_y = world_y - active.grab_delta.1;
                    record.offset_x = new_x.round() as i32;
                    record.offset_y = new_y.round() as i32;
                    result.changed = true;
                    ui.ctx().request_repaint();
                } else {
                    clear_drag = true;
                }
            }
            if !ui.input(|i| i.pointer.primary_down()) {
                clear_drag = true;
            }
            hovered_idx = Some(active.record_index);
        } else if response.drag_started() {
            if let Some(idx) = hovered_idx {
                if let Some(pos) = pointer_pos {
                    if let Some(record) = records.get(idx) {
                        let (world_x, world_y) = transform.unproject(pos);
                        drag_state.active = Some(FormationDrag {
                            record_index: idx,
                            grab_delta: (
                                world_x - record.offset_x as f32,
                                world_y - record.offset_y as f32,
                            ),
                        });
                        new_selection = Some(idx);
                    }
                }
            }
        }
    } else {
        if let Some(active) = &gesture_state.active {
            if active.wave_index != selected_wave || active.mode != mode {
                gesture_state.clear();
            }
        }
        if let Some(active) = gesture_state.active.as_mut() {
            if let Some(pos) = pointer_pos {
                let pointer_world = transform.unproject(pos);
                match active.mode {
                    WaveEditMode::Move => {
                        let dx = pointer_world.0 - active.start_pointer.0;
                        let dy = pointer_world.1 - active.start_pointer.1;
                        for (idx, (orig_x, orig_y)) in &active.original_positions {
                            if let Some(record) = records.get_mut(*idx) {
                                record.offset_x = (orig_x + dx).round() as i32;
                                record.offset_y = (orig_y + dy).round() as i32;
                            }
                        }
                    }
                    WaveEditMode::Rotate => {
                        let angle_now = angle_between(active.anchor, pointer_world);
                        let delta = angle_now - active.initial_angle;
                        for (idx, (orig_x, orig_y)) in &active.original_positions {
                            if let Some(record) = records.get_mut(*idx) {
                                let rotated =
                                    rotate_around((*orig_x, *orig_y), active.anchor, delta);
                                record.offset_x = rotated.0.round() as i32;
                                record.offset_y = rotated.1.round() as i32;
                            }
                        }
                    }
                    WaveEditMode::Scale => {
                        let dist = distance(active.anchor, pointer_world).max(0.001);
                        let scale = (dist / active.initial_radius).clamp(0.2, 5.0);
                        for (idx, (orig_x, orig_y)) in &active.original_positions {
                            if let Some(record) = records.get_mut(*idx) {
                                let scaled = scale_from((*orig_x, *orig_y), active.anchor, scale);
                                record.offset_x = scaled.0.round() as i32;
                                record.offset_y = scaled.1.round() as i32;
                            }
                        }
                    }
                    WaveEditMode::Points => {}
                }
                result.changed = true;
                ui.ctx().request_repaint();
            }
            if !ui.input(|i| i.pointer.primary_down()) {
                gesture_state.clear();
            }
        } else if response.drag_started() {
            if let Some(pos) = pointer_pos {
                let pointer_world = transform.unproject(pos);
                let anchor = wave_centroid(&records[start..end]);
                let originals = (start..end)
                    .map(|idx| {
                        let rec = &records[idx];
                        (idx, (rec.offset_x as f32, rec.offset_y as f32))
                    })
                    .collect();
                gesture_state.begin(selected_wave, mode, anchor, pointer_world, originals);
            }
        }
    }
    if clear_drag {
        drag_state.clear();
    }

    for (idx, pos, _) in &points {
        let row = idx / FORMATION_ROW_SIZE;
        let base_color = ROW_COLORS[row % ROW_COLORS.len()];
        let (color, radius) = if *idx == selected_index {
            (Color32::from_rgb(64, 196, 255), 9.0)
        } else if Some(*idx) == hovered_idx {
            (base_color.gamma_multiply(1.2), 7.0)
        } else {
            (base_color, 6.0)
        };
        painter.circle_filled(*pos, radius, color);
        if *idx == start {
            painter.circle_stroke(*pos, radius + 3.5, Stroke::new(1.5, Color32::WHITE));
        }
        painter.text(
            Pos2::new(pos.x + 6.0, pos.y - 6.0),
            Align2::LEFT_BOTTOM,
            format!("{}:{}", row, idx % FORMATION_ROW_SIZE),
            FontId::proportional(AUX_LABEL_FONT),
            Color32::from_gray(210),
        );
    }

    if response.clicked() {
        if let Some(idx) = hovered_idx {
            new_selection = Some(idx);
        }
    }

    if let Some(idx) = new_selection {
        result.selection = Some(idx);
    }
    result
}

fn draw_timeline_canvas(
    ui: &mut egui::Ui,
    records: &[FormationRecord],
    selected_index: usize,
    playhead: Option<f32>,
) -> CanvasResult {
    let mut result = CanvasResult::default();
    let width = ui.available_width().max(320.0);
    let height = 320.0;
    let (rect, response) = ui.allocate_exact_size(Vec2::new(width, height), egui::Sense::click());
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 4.0, Color32::from_rgb(18, 16, 24));
    painter.rect_stroke(rect, 4.0, Stroke::new(1.0, Color32::from_gray(70)));

    let mut min_delay = i32::MAX;
    let mut max_delay = i32::MIN;
    for record in records {
        min_delay = min_delay.min(record.spawn_delay_start);
        max_delay = max_delay.max(record.spawn_delay_start);
    }
    if min_delay == i32::MAX {
        return result;
    }
    let pad = 24.0;
    let usable_w = (rect.width() - pad * 2.0).max(1.0);
    let usable_h = (rect.height() - pad * 2.0).max(1.0);
    let span_x = (max_delay - min_delay).max(1) as f32;
    let scale_x = usable_w / span_x;
    let rows = (records.len() + FORMATION_ROW_SIZE - 1) / FORMATION_ROW_SIZE;
    let scale_y = usable_h / rows.max(1) as f32;

    let project = |row: usize, delay: i32| -> Pos2 {
        let px = rect.left() + pad + (delay - min_delay) as f32 * scale_x;
        let py = rect.top() + pad + row as f32 * scale_y;
        Pos2::new(px, py)
    };

    let timeline_color = Color32::from_gray(80);
    for row in 0..rows {
        let y = rect.top() + pad + row as f32 * scale_y;
        painter.line_segment(
            [
                Pos2::new(rect.left() + pad, y),
                Pos2::new(rect.right() - pad, y),
            ],
            Stroke::new(1.0, timeline_color),
        );
    }

    for tick in 0..=8 {
        let t = min_delay as f32 + span_x / 8f32 * tick as f32;
        let x = rect.left() + pad + (t - min_delay as f32) * scale_x;
        painter.line_segment(
            [
                Pos2::new(x, rect.top() + pad - 4.0),
                Pos2::new(x, rect.bottom() - pad),
            ],
            Stroke::new(0.5, timeline_color),
        );
        painter.text(
            Pos2::new(x, rect.top() + 4.0),
            Align2::CENTER_TOP,
            format!("{:.0}", t),
            FontId::proportional(10.0),
            Color32::from_gray(170),
        );
    }

    if let Some(playhead) = playhead {
        let clamped = playhead
            .max(min_delay as f32)
            .min(min_delay as f32 + span_x);
        let x = rect.left() + pad + (clamped - min_delay as f32) * scale_x;
        painter.line_segment(
            [
                Pos2::new(x, rect.top() + pad - 6.0),
                Pos2::new(x, rect.bottom() - pad + 6.0),
            ],
            Stroke::new(1.5, Color32::from_rgb(64, 196, 255)),
        );
    }

    let mut hovered_idx: Option<usize> = None;
    if let Some(pos) = response.hover_pos() {
        hovered_idx = records
            .iter()
            .enumerate()
            .map(|(idx, record)| {
                let p = project(idx / FORMATION_ROW_SIZE, record.spawn_delay_start);
                (idx, p.distance(pos))
            })
            .min_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
            .and_then(|(idx, dist)| if dist < 18.0 { Some(idx) } else { None });
        painter.circle_stroke(pos, 6.0, Stroke::new(1.0, Color32::from_gray(120)));
    }

    if let Some(idx) = hovered_idx {
        if let Some(record) = records.get(idx) {
            response.clone().on_hover_text(format!(
                "Row {} slot {}\nSpawn start: {}\nSpawn window: {}",
                idx / FORMATION_ROW_SIZE,
                idx % FORMATION_ROW_SIZE,
                record.spawn_delay_start,
                record.spawn_window_secondary
            ));
        }
    }

    for (idx, record) in records.iter().enumerate() {
        let row = idx / FORMATION_ROW_SIZE;
        let base_color = ROW_COLORS[row % ROW_COLORS.len()];
        let pos = project(row, record.spawn_delay_start);
        let is_active = playhead
            .map(|t| formation_record_active(record, t))
            .unwrap_or(false);
        let (color, radius) = if idx == selected_index {
            (Color32::from_rgb(64, 196, 255), 8.0)
        } else if is_active {
            (Color32::from_rgb(255, 221, 117), 7.5)
        } else if Some(idx) == hovered_idx {
            (base_color.gamma_multiply(1.2), 7.0)
        } else {
            (base_color, 5.0)
        };
        painter.circle_filled(pos, radius, color);
        painter.text(
            Pos2::new(pos.x + 6.0, pos.y - 4.0),
            Align2::LEFT_CENTER,
            format!(
                "Row {} · slot {} · t={}",
                row,
                idx % FORMATION_ROW_SIZE,
                record.spawn_delay_start
            ),
            FontId::proportional(10.0),
            Color32::from_gray(220),
        );
    }

    if response.clicked() {
        if let Some(idx) = hovered_idx {
            result.selection = Some(idx);
        }
    }

    result
}
#[derive(Debug, Clone, Serialize, Deserialize)]
struct DescriptorRoot {
    record_size: u32,
    total_blocks: u32,
    sections: Sections,
}

impl DescriptorRoot {
    fn refresh_metadata(&mut self) {
        if let Some(section) = self.sections.enemy_formations.as_mut() {
            section.record_count = section.records.len();
        }
        self.sections.refresh_aux_counts();
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Sections {
    enemy_formations: Option<FormationSection>,
    promotion_banner_paths: Option<AuxSection>,
    meteor_arc_paths: Option<AuxSection>,
    boss_callout_paths: Option<AuxSection>,
    rank_marker_gates: Option<AuxSection>,
    reward_ribbon_paths: Option<AuxSection>,
    hud_flash_counters: Option<AuxSection>,
    news_ticker_globals: Option<AuxSection>,
}

impl Sections {
    fn get_aux(&self, kind: AuxSectionKind) -> Option<&AuxSection> {
        match kind {
            AuxSectionKind::PromotionBannerPaths => self.promotion_banner_paths.as_ref(),
            AuxSectionKind::MeteorArcPaths => self.meteor_arc_paths.as_ref(),
            AuxSectionKind::BossCalloutPaths => self.boss_callout_paths.as_ref(),
            AuxSectionKind::RankMarkerGates => self.rank_marker_gates.as_ref(),
            AuxSectionKind::RewardRibbonPaths => self.reward_ribbon_paths.as_ref(),
            AuxSectionKind::HudFlashCounters => self.hud_flash_counters.as_ref(),
            AuxSectionKind::NewsTickerGlobals => self.news_ticker_globals.as_ref(),
        }
    }

    fn get_aux_mut(&mut self, kind: AuxSectionKind) -> Option<&mut AuxSection> {
        match kind {
            AuxSectionKind::PromotionBannerPaths => self.promotion_banner_paths.as_mut(),
            AuxSectionKind::MeteorArcPaths => self.meteor_arc_paths.as_mut(),
            AuxSectionKind::BossCalloutPaths => self.boss_callout_paths.as_mut(),
            AuxSectionKind::RankMarkerGates => self.rank_marker_gates.as_mut(),
            AuxSectionKind::RewardRibbonPaths => self.reward_ribbon_paths.as_mut(),
            AuxSectionKind::HudFlashCounters => self.hud_flash_counters.as_mut(),
            AuxSectionKind::NewsTickerGlobals => self.news_ticker_globals.as_mut(),
        }
    }

    fn refresh_aux_counts(&mut self) {
        fn update_count(section: &mut Option<AuxSection>) {
            if let Some(sec) = section {
                sec.record_count = sec.records.len();
            }
        }

        update_count(&mut self.promotion_banner_paths);
        update_count(&mut self.meteor_arc_paths);
        update_count(&mut self.boss_callout_paths);
        update_count(&mut self.rank_marker_gates);
        update_count(&mut self.reward_ribbon_paths);
        update_count(&mut self.hud_flash_counters);
        update_count(&mut self.news_ticker_globals);
    }
}

impl FormationSection {
    fn add_wave(&mut self) -> usize {
        for _ in 0..FORMATION_ROW_SIZE {
            self.records.push(FormationRecord::default());
        }
        wave_count(self).saturating_sub(1)
    }

    fn clone_wave(&mut self, wave_index: usize) -> Option<usize> {
        let (start, end) = wave_range(self, wave_index)?;
        let clone = self.records[start..end].to_vec();
        self.records.extend(clone);
        Some(wave_count(self).saturating_sub(1))
    }

    fn clone_wave_mirrored(&mut self, wave_index: usize, axis: MirrorAxis) -> Option<usize> {
        let (start, end) = wave_range(self, wave_index)?;
        let mut clone = self.records[start..end].to_vec();
        for record in &mut clone {
            match axis {
                MirrorAxis::Horizontal => record.offset_x = -record.offset_x,
                MirrorAxis::Vertical => record.offset_y = -record.offset_y,
            }
        }
        self.records.extend(clone);
        Some(wave_count(self).saturating_sub(1))
    }

    fn remove_wave(&mut self, wave_index: usize) -> bool {
        if let Some((start, end)) = wave_range(self, wave_index) {
            self.records.drain(start..end);
            true
        } else {
            false
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FormationSection {
    start_block: i32,
    end_block: i32,
    record_count: usize,
    records: Vec<FormationRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct FormationRecord {
    spawn_delay_start: i32,
    spawn_delay_increment: i32,
    spawn_delay_secondary: i32,
    spawn_window_secondary: i32,
    offset_x: i32,
    offset_y: i32,
    enemy_type: i32,
    behavior_flags: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AuxSection {
    start_block: i32,
    end_block: i32,
    record_count: usize,
    records: Vec<AuxRecord>,
    #[serde(default)]
    source_section: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct AuxRecord {
    origin_x: i32,
    origin_y: i32,
    target_x: i32,
    target_y: i32,
    velocity_x: i32,
    velocity_y: i32,
    timer_primary: i32,
    timer_secondary: i32,
    #[serde(default)]
    segment_name: Option<String>,
}

#[derive(Default)]
struct FormationDragState {
    active: Option<FormationDrag>,
}

struct FormationDrag {
    record_index: usize,
    grab_delta: (f32, f32),
}

impl FormationDragState {
    fn clear(&mut self) {
        self.active = None;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WaveEditMode {
    Points,
    Move,
    Rotate,
    Scale,
}

impl WaveEditMode {
    fn label(self) -> &'static str {
        match self {
            WaveEditMode::Points => "POINTS",
            WaveEditMode::Move => "MOVE",
            WaveEditMode::Rotate => "ROTATE",
            WaveEditMode::Scale => "ZOOM",
        }
    }
}

#[derive(Default)]
struct WaveGestureState {
    active: Option<WaveGesture>,
}

struct WaveGesture {
    wave_index: usize,
    mode: WaveEditMode,
    anchor: (f32, f32),
    start_pointer: (f32, f32),
    initial_angle: f32,
    initial_radius: f32,
    original_positions: Vec<(usize, (f32, f32))>,
}

impl WaveGestureState {
    fn clear(&mut self) {
        self.active = None;
    }

    fn begin(
        &mut self,
        wave_index: usize,
        mode: WaveEditMode,
        anchor: (f32, f32),
        start_pointer: (f32, f32),
        original_positions: Vec<(usize, (f32, f32))>,
    ) {
        let initial_angle = angle_between(anchor, start_pointer);
        let initial_radius = distance(anchor, start_pointer).max(0.001);
        self.active = Some(WaveGesture {
            wave_index,
            mode,
            anchor,
            start_pointer,
            initial_angle,
            initial_radius,
            original_positions,
        });
    }
}

#[derive(Default)]
struct AuxDragState {
    active: Option<AuxDrag>,
}

struct AuxDrag {
    record_index: usize,
    handle: AuxHandleKind,
    grab_delta: (f32, f32),
}

impl AuxDragState {
    fn clear(&mut self) {
        self.active = None;
    }
}

#[derive(Debug, Clone, Copy)]
struct AuxPlaybackSample {
    record_index: usize,
    position: (f32, f32),
    is_gap: bool,
}

#[derive(Debug, Default, Clone, Copy)]
struct AuxPlaybackState {
    playhead: f32,
    is_playing: bool,
}

impl AuxPlaybackState {
    fn reset(&mut self) {
        self.playhead = 0.0;
        self.is_playing = false;
    }
}

#[derive(Debug, Default, Clone, Copy)]
struct FormationPlaybackState {
    playhead: f32,
    is_playing: bool,
}

impl FormationPlaybackState {
    fn reset(&mut self) {
        self.playhead = 0.0;
        self.is_playing = false;
    }
}

#[derive(Debug, Clone)]
struct AuxTimeline {
    phases: Vec<TimelinePhase>,
    total_duration: f32,
}

#[derive(Debug, Clone)]
struct TimelinePhase {
    start: f32,
    duration: f32,
    kind: TimelinePhaseKind,
}

#[derive(Debug, Clone)]
enum TimelinePhaseKind {
    Gap {
        record_index: usize,
        hold_position: (f32, f32),
    },
    Motion {
        record_index: usize,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ViewMode {
    Formations,
    Aux(AuxSectionKind),
}

impl ViewMode {
    fn label(&self) -> &'static str {
        match self {
            ViewMode::Formations => "Enemy Formations",
            ViewMode::Aux(kind) => kind.display_name(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AuxSectionKind {
    PromotionBannerPaths,
    MeteorArcPaths,
    BossCalloutPaths,
    RankMarkerGates,
    RewardRibbonPaths,
    HudFlashCounters,
    NewsTickerGlobals,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AuxHandleKind {
    Origin,
    Target,
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct AuxHandleRef {
    record_index: usize,
    kind: AuxHandleKind,
}

impl AuxSectionKind {
    const ALL: &'static [AuxSectionKind] = &[
        AuxSectionKind::PromotionBannerPaths,
        AuxSectionKind::MeteorArcPaths,
        AuxSectionKind::BossCalloutPaths,
        AuxSectionKind::RankMarkerGates,
        AuxSectionKind::RewardRibbonPaths,
        AuxSectionKind::HudFlashCounters,
        AuxSectionKind::NewsTickerGlobals,
    ];

    fn display_name(self) -> &'static str {
        match self {
            AuxSectionKind::PromotionBannerPaths => "Promotion Banner Paths",
            AuxSectionKind::MeteorArcPaths => "Meteor Arc Paths",
            AuxSectionKind::BossCalloutPaths => "Boss Callout Paths",
            AuxSectionKind::RankMarkerGates => "Rank Marker Gates",
            AuxSectionKind::RewardRibbonPaths => "Reward Ribbon Paths",
            AuxSectionKind::HudFlashCounters => "HUD Flash Counters",
            AuxSectionKind::NewsTickerGlobals => "News Ticker Globals",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FormationCanvasMode {
    HudOffsets,
    SpawnTimeline,
}
impl LevelEditorApp {
    fn render_aux_section(&mut self, ui: &mut egui::Ui, kind: AuxSectionKind) {
        let mut playback_overlay: Option<AuxPlaybackSample> = None;
        {
            let Some(section_meta) = self
                .descriptor
                .as_ref()
                .and_then(|desc| desc.sections.get_aux(kind))
            else {
                ui.centered_and_justified(|ui| {
                    ui.label("Selected auxiliary section is missing in this descriptor.");
                });
                return;
            };

            ui.heading(kind.display_name());
            if let Some(source) = &section_meta.source_section {
                ui.label(format!("Source: {}", source));
            }
            ui.label("Click segments on the preview or rows in the table to inspect raw values.");
            ui.label("Playback animates the path so you can visualize how the HUD element moves.");

            if let Some(timeline) = build_aux_timeline_for_kind(kind, section_meta) {
                advance_playback_state(&mut self.aux_playback, ui.ctx(), timeline.total_duration);
                playback_overlay =
                    sample_aux_timeline(&timeline, section_meta, self.aux_playback.playhead);
                render_playback_controls(&mut self.aux_playback, ui, &timeline);
                ui.separator();
            } else {
                self.aux_playback.reset();
            }
        }

        let mut dirty_after_section = false;
        let Some(desc) = self.descriptor.as_mut() else {
            return;
        };
        let Some(section) = desc.sections.get_aux_mut(kind) else {
            return;
        };

        let mut selected_idx = self
            .selected_aux_index
            .min(section.records.len().saturating_sub(1));
        let canvas_outcome = draw_aux_paths_canvas(
            ui,
            &mut section.records,
            selected_idx,
            playback_overlay.as_ref(),
            &mut self.aux_drag,
        );
        if let Some(idx) = canvas_outcome.selection {
            selected_idx = idx;
        }
        if canvas_outcome.changed {
            dirty_after_section = true;
        }
        ui.separator();

        egui::ScrollArea::vertical()
            .id_source(format!("aux_table_{:?}", kind))
            .show(ui, |ui| {
                egui::Grid::new(format!("aux_grid_{:?}", kind))
                    .striped(true)
                    .min_col_width(90.0)
                    .show(ui, |ui| {
                        ui.strong("Idx");
                        ui.strong("Segment");
                        ui.strong("Origin");
                        ui.strong("Target");
                        ui.strong("Velocity");
                        ui.strong("Timers");
                        ui.end_row();
                        for (idx, record) in section.records.iter().enumerate() {
                            let selected = selected_idx == idx;
                            let label = record
                                .segment_name
                                .as_deref()
                                .unwrap_or_else(|| "<unnamed>");
                            let resp = ui.selectable_label(selected, idx.to_string());
                            if resp.clicked() {
                                selected_idx = idx;
                            }
                            ui.label(label);
                            ui.label(format!("{}, {}", record.origin_x, record.origin_y));
                            ui.label(format!("{}, {}", record.target_x, record.target_y));
                            ui.label(format!("{}, {}", record.velocity_x, record.velocity_y));
                            ui.label(format!(
                                "{} / {}",
                                record.timer_primary, record.timer_secondary
                            ));
                            ui.end_row();
                        }
                    });
            });
        ui.separator();

        let heading = section
            .records
            .get(selected_idx)
            .and_then(|r| r.segment_name.clone())
            .unwrap_or_else(|| "unnamed segment".to_string());
        if section.records.get(selected_idx).is_some() {
            ui.heading(format!("Record {} ({heading})", selected_idx));
        }
        if let Some(record) = section.records.get_mut(selected_idx) {
            let mut changed = false;
            egui::Grid::new("aux_details").show(ui, |ui| {
                changed |= drag_i32_row(ui, "Origin X", &mut record.origin_x, -5_000..=5_000);
                changed |= drag_i32_row(ui, "Origin Y", &mut record.origin_y, -5_000..=5_000);
                changed |= drag_i32_row(ui, "Target X", &mut record.target_x, -5_000..=5_000);
                changed |= drag_i32_row(ui, "Target Y", &mut record.target_y, -5_000..=5_000);
                changed |= drag_i32_row(ui, "Velocity X", &mut record.velocity_x, -1_000..=1_000);
                changed |= drag_i32_row(ui, "Velocity Y", &mut record.velocity_y, -1_000..=1_000);
                changed |= drag_i32_row(
                    ui,
                    "Timer Primary",
                    &mut record.timer_primary,
                    -10_000..=10_000,
                );
                changed |= drag_i32_row(
                    ui,
                    "Timer Secondary",
                    &mut record.timer_secondary,
                    -10_000..=10_000,
                );
                ui.label("Segment Label");
                let mut label_text = record.segment_name.clone().unwrap_or_default();
                if ui.text_edit_singleline(&mut label_text).changed() {
                    let trimmed = label_text.trim();
                    if trimmed.is_empty() {
                        record.segment_name = None;
                    } else {
                        record.segment_name = Some(trimmed.to_string());
                    }
                    changed = true;
                }
                ui.end_row();
            });
            if changed {
                dirty_after_section = true;
            }
        }

        self.selected_aux_index = selected_idx;

        if dirty_after_section {
            self.mark_dirty();
        }
    }
}

fn draw_aux_paths_canvas(
    ui: &mut egui::Ui,
    records: &mut [AuxRecord],
    selected_index: usize,
    playback_sample: Option<&AuxPlaybackSample>,
    drag_state: &mut AuxDragState,
) -> CanvasResult {
    let mut result = CanvasResult::default();
    if records.is_empty() {
        ui.label("No records to display.");
        return result;
    }
    let width = ui.available_width().max(320.0);
    let height = 360.0;
    let (rect, response) =
        ui.allocate_exact_size(Vec2::new(width, height), egui::Sense::click_and_drag());
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 4.0, Color32::from_rgb(16, 18, 24));
    painter.rect_stroke(rect, 4.0, Stroke::new(1.0, Color32::from_gray(70)));

    let mut min_x = 0f32;
    let mut max_x = 0f32;
    let mut min_y = 0f32;
    let mut max_y = 0f32;
    for record in records.iter() {
        for (x, y) in [
            (record.origin_x, record.origin_y),
            (record.target_x, record.target_y),
        ] {
            let xf = x as f32;
            let yf = y as f32;
            min_x = min_x.min(xf);
            max_x = max_x.max(xf);
            min_y = min_y.min(yf);
            max_y = max_y.max(yf);
        }
    }
    let pad = 24.0;
    let usable_w = (rect.width() - pad * 2.0).max(1.0);
    let usable_h = (rect.height() - pad * 2.0).max(1.0);
    let span_x = (max_x - min_x).abs().max(40.0);
    let span_y = (max_y - min_y).abs().max(40.0);
    let scale_x = usable_w / span_x;
    let scale_y = usable_h / span_y;
    let transform = CanvasTransform::new(rect, pad, min_x, min_y, scale_x, scale_y);

    let axis_color = Color32::from_gray(90);
    if min_x <= 0.0 && max_x >= 0.0 {
        let x = transform.project(0.0, min_y).x;
        painter.line_segment(
            [
                Pos2::new(x, rect.top() + pad),
                Pos2::new(x, rect.bottom() - pad),
            ],
            Stroke::new(1.0, axis_color),
        );
    }
    if min_y <= 0.0 && max_y >= 0.0 {
        let y = transform.project(min_x, 0.0).y;
        painter.line_segment(
            [
                Pos2::new(rect.left() + pad, y),
                Pos2::new(rect.right() - pad, y),
            ],
            Stroke::new(1.0, axis_color),
        );
    }

    #[derive(Clone, Copy)]
    struct AuxSegmentVisual {
        origin: Pos2,
        target: Pos2,
    }

    let mut visuals: Vec<AuxSegmentVisual> = records
        .iter()
        .map(|record| AuxSegmentVisual {
            origin: transform.project(record.origin_x as f32, record.origin_y as f32),
            target: transform.project(record.target_x as f32, record.target_y as f32),
        })
        .collect();

    let mut hovered_segment: Option<usize> = None;
    let mut hovered_handle: Option<AuxHandleRef> = None;
    if let Some(pos) = response.hover_pos() {
        let mut best_segment: (f32, Option<usize>) = (f32::INFINITY, None);
        let mut best_handle: (f32, Option<AuxHandleRef>) = (f32::INFINITY, None);
        for (idx, visual) in visuals.iter().enumerate() {
            let dist_seg = distance_to_segment(visual.origin, visual.target, pos);
            if dist_seg < best_segment.0 && dist_seg < 18.0 {
                best_segment = (dist_seg, Some(idx));
            }
            let dist_origin = visual.origin.distance(pos);
            if dist_origin < best_handle.0 && dist_origin < 14.0 {
                best_handle = (
                    dist_origin,
                    Some(AuxHandleRef {
                        record_index: idx,
                        kind: AuxHandleKind::Origin,
                    }),
                );
            }
            let dist_target = visual.target.distance(pos);
            if dist_target < best_handle.0 && dist_target < 14.0 {
                best_handle = (
                    dist_target,
                    Some(AuxHandleRef {
                        record_index: idx,
                        kind: AuxHandleKind::Target,
                    }),
                );
            }
        }
        hovered_segment = best_segment.1;
        hovered_handle = best_handle.1;
        if hovered_handle.is_some() || hovered_segment.is_some() {
            painter.circle_stroke(pos, 6.0, Stroke::new(1.0, Color32::from_gray(120)));
        }
    }

    let pointer_pos = response.interact_pointer_pos();
    let mut new_selection: Option<usize> = None;
    let mut clear_drag = false;
    let mut dirty_visual: Option<usize> = None;

    if let Some(active) = drag_state.active.as_mut() {
        if let Some(pos) = pointer_pos {
            if let Some(record) = records.get_mut(active.record_index) {
                let (world_x, world_y) = transform.unproject(pos);
                let new_x = world_x - active.grab_delta.0;
                let new_y = world_y - active.grab_delta.1;
                match active.handle {
                    AuxHandleKind::Origin => {
                        record.origin_x = new_x.round() as i32;
                        record.origin_y = new_y.round() as i32;
                    }
                    AuxHandleKind::Target => {
                        record.target_x = new_x.round() as i32;
                        record.target_y = new_y.round() as i32;
                    }
                }
                result.changed = true;
                dirty_visual = Some(active.record_index);
                hovered_segment = Some(active.record_index);
                hovered_handle = Some(AuxHandleRef {
                    record_index: active.record_index,
                    kind: active.handle,
                });
                ui.ctx().request_repaint();
            } else {
                clear_drag = true;
            }
        }
        if !ui.input(|i| i.pointer.primary_down()) {
            clear_drag = true;
        }
    } else if response.drag_started() {
        if let Some(handle_ref) = hovered_handle {
            if let Some(pos) = pointer_pos {
                if let Some(record) = records.get(handle_ref.record_index) {
                    let current = match handle_ref.kind {
                        AuxHandleKind::Origin => (record.origin_x as f32, record.origin_y as f32),
                        AuxHandleKind::Target => (record.target_x as f32, record.target_y as f32),
                    };
                    let (world_x, world_y) = transform.unproject(pos);
                    drag_state.active = Some(AuxDrag {
                        record_index: handle_ref.record_index,
                        handle: handle_ref.kind,
                        grab_delta: (world_x - current.0, world_y - current.1),
                    });
                    new_selection = Some(handle_ref.record_index);
                }
            }
        }
    }

    if clear_drag {
        drag_state.clear();
    }
    if let Some(idx) = dirty_visual {
        if let (Some(visual), Some(record)) = (visuals.get_mut(idx), records.get(idx)) {
            visual.origin = transform.project(record.origin_x as f32, record.origin_y as f32);
            visual.target = transform.project(record.target_x as f32, record.target_y as f32);
        }
    }

    let active_handle = drag_state.active.as_ref().map(|drag| AuxHandleRef {
        record_index: drag.record_index,
        kind: drag.handle,
    });

    for (idx, visual) in visuals.iter().enumerate() {
        let selected = idx == selected_index;
        let hovered = hovered_segment == Some(idx);
        let stroke = if selected {
            Stroke::new(2.0, Color32::from_rgb(64, 196, 255))
        } else if hovered {
            Stroke::new(1.6, Color32::from_gray(200))
        } else {
            Stroke::new(1.2, Color32::from_gray(160))
        };
        painter.line_segment([visual.origin, visual.target], stroke);

        let label_text = records[idx]
            .segment_name
            .clone()
            .unwrap_or_else(|| format!("#{idx}"));
        painter.text(
            Pos2::new(visual.origin.x + 8.0, visual.origin.y - 4.0),
            Align2::LEFT_TOP,
            label_text,
            FontId::proportional(AUX_LABEL_FONT),
            Color32::from_gray(210),
        );

        let origin_ref = AuxHandleRef {
            record_index: idx,
            kind: AuxHandleKind::Origin,
        };
        let target_ref = AuxHandleRef {
            record_index: idx,
            kind: AuxHandleKind::Target,
        };
        draw_aux_handle(
            &painter,
            visual.origin,
            origin_ref,
            hovered_handle,
            active_handle,
        );
        draw_aux_handle(
            &painter,
            visual.target,
            target_ref,
            hovered_handle,
            active_handle,
        );
    }

    if let Some(sample) = playback_sample {
        let pos = transform.project(sample.position.0, sample.position.1);
        let fill = if sample.is_gap {
            Color32::from_rgb(200, 210, 255)
        } else {
            Color32::from_rgb(255, 176, 94)
        };
        painter.circle_filled(pos, 6.5, fill);
        painter.circle_stroke(pos, 9.0, Stroke::new(1.5, Color32::from_rgb(254, 236, 180)));
        painter.text(
            Pos2::new(pos.x + 8.0, pos.y + 6.0),
            Align2::LEFT_TOP,
            format!("#{}", sample.record_index),
            FontId::proportional(10.0),
            Color32::from_gray(230),
        );
    }

    if response.clicked() {
        if let Some(handle) = hovered_handle {
            new_selection = Some(handle.record_index);
        } else if let Some(idx) = hovered_segment {
            new_selection = Some(idx);
        }
    }

    if let Some(idx) = new_selection {
        result.selection = Some(idx);
    }
    result
}

fn advance_playback_state(
    playback: &mut AuxPlaybackState,
    ctx: &egui::Context,
    total_duration: f32,
) {
    let max_time = total_duration.max(1.0);
    playback.playhead = playback.playhead.clamp(0.0, max_time);
    if playback.is_playing {
        let frame_dt = ctx.input(|i| i.stable_dt).max(0.0);
        let advance = if frame_dt > 0.0 { frame_dt * 60.0 } else { 1.0 };
        playback.playhead += advance;
        if playback.playhead >= max_time {
            playback.playhead = max_time;
            playback.is_playing = false;
        } else {
            ctx.request_repaint();
        }
    }
}

fn render_playback_controls(
    playback: &mut AuxPlaybackState,
    ui: &mut egui::Ui,
    timeline: &AuxTimeline,
) {
    ui.group(|ui| {
        ui.horizontal(|ui| {
            let play_label = if playback.is_playing { "Pause" } else { "Play" };
            if ui.button(play_label).clicked() {
                if playback.is_playing {
                    playback.is_playing = false;
                } else {
                    if (playback.playhead - timeline.total_duration).abs() < f32::EPSILON {
                        playback.playhead = 0.0;
                    }
                    playback.is_playing = true;
                }
            }
            if ui.button("Reset").clicked() {
                playback.reset();
            }
            ui.label(format!(
                "Frame {:.0} / {:.0}",
                playback.playhead,
                timeline.total_duration
            ));
        });
        ui.add_space(4.0);
        let slider = egui::Slider::new(
            &mut playback.playhead,
            0.0..=timeline.total_duration.max(1.0),
        )
        .text("Scrub frames");
        if ui.add(slider).changed() {
            playback.is_playing = false;
        }
        ui.small(
            "Timing heuristics use timer fields first, then fall back to velocity-derived travel time.",
        );
    });
}

fn formation_total_duration(section: &FormationSection) -> f32 {
    section
        .records
        .iter()
        .map(|record| {
            let start = record.spawn_delay_start.max(0) as f32;
            let window = record.spawn_window_secondary.max(0) as f32;
            if window <= 0.0 { start } else { start + window }
        })
        .fold(0.0, f32::max)
        .max(0.0)
}

fn advance_formation_playback_state(
    playback: &mut FormationPlaybackState,
    ctx: &egui::Context,
    total_duration: f32,
) {
    let max_time = total_duration.max(1.0);
    playback.playhead = playback.playhead.clamp(0.0, max_time);
    if playback.is_playing {
        let frame_dt = ctx.input(|i| i.stable_dt).max(0.0);
        let advance = if frame_dt > 0.0 { frame_dt * 60.0 } else { 1.0 };
        playback.playhead += advance;
        if playback.playhead >= max_time {
            playback.playhead = max_time;
            playback.is_playing = false;
        } else {
            ctx.request_repaint();
        }
    }
}

fn render_formation_playback_controls(
    playback: &mut FormationPlaybackState,
    ui: &mut egui::Ui,
    total_duration: f32,
) {
    let usable_duration = total_duration.max(1.0);
    ui.group(|ui| {
        ui.horizontal(|ui| {
            let play_label = if playback.is_playing { "Pause" } else { "Play" };
            if ui.button(play_label).clicked() {
                if playback.is_playing {
                    playback.is_playing = false;
                } else {
                    if (playback.playhead - usable_duration).abs() < f32::EPSILON {
                        playback.playhead = 0.0;
                    }
                    playback.is_playing = true;
                }
            }
            if ui.button("Reset").clicked() {
                playback.reset();
            }
            ui.label(format!(
                "Frame {:.0} / {:.0}",
                playback.playhead.min(usable_duration),
                usable_duration
            ));
        });
        ui.add_space(4.0);
        let slider = egui::Slider::new(&mut playback.playhead, 0.0..=usable_duration)
            .text("Formation timeline (frames)");
        if ui.add(slider).changed() {
            playback.is_playing = false;
        }
        ui.small("Frames correspond to spawn delays from the .lvd formation records.");
    });
}

fn formation_record_active(record: &FormationRecord, playhead: f32) -> bool {
    let start = record.spawn_delay_start as f32;
    if playhead < start {
        return false;
    }
    let window = record.spawn_window_secondary.max(0) as f32;
    if window <= 0.0 {
        (playhead - start).abs() < 1.0
    } else {
        playhead <= start + window
    }
}

fn draw_aux_handle(
    painter: &Painter,
    pos: Pos2,
    handle: AuxHandleRef,
    hovered: Option<AuxHandleRef>,
    active: Option<AuxHandleRef>,
) {
    let base_color = match handle.kind {
        AuxHandleKind::Origin => Color32::from_rgb(200, 200, 200),
        AuxHandleKind::Target => Color32::from_rgb(120, 190, 255),
    };
    let is_active = active == Some(handle);
    let is_hovered = hovered == Some(handle);
    let (color, radius) = if is_active {
        (Color32::from_rgb(255, 210, 120), 7.0)
    } else if is_hovered {
        (base_color.gamma_multiply(1.25), 6.0)
    } else {
        let default_radius = if matches!(handle.kind, AuxHandleKind::Origin) {
            4.5
        } else {
            4.0
        };
        (base_color, default_radius)
    };
    painter.circle_filled(pos, radius, color);
    if is_active {
        painter.circle_stroke(
            pos,
            radius + 2.0,
            Stroke::new(1.2, Color32::from_rgb(255, 235, 190)),
        );
    }
}

fn write_section_value<T: Serialize>(raw: &mut Value, key: &str, section: &T) -> Result<()> {
    let root = raw
        .as_object_mut()
        .ok_or_else(|| anyhow!("Descriptor JSON root is not an object"))?;
    let sections_entry = root
        .entry("sections")
        .or_insert_with(|| Value::Object(serde_json::Map::new()));
    if !sections_entry.is_object() {
        *sections_entry = Value::Object(serde_json::Map::new());
    }
    sections_entry
        .as_object_mut()
        .unwrap()
        .insert(key.to_string(), serde_json::to_value(section)?);
    Ok(())
}

fn drag_i32_row(
    ui: &mut egui::Ui,
    label: &str,
    value: &mut i32,
    range: RangeInclusive<i32>,
) -> bool {
    ui.label(label);
    let changed = ui
        .add(
            DragValue::new(value)
                .clamp_range(range)
                .speed(1.0)
                .update_while_editing(true),
        )
        .changed();
    ui.end_row();
    changed
}

fn build_aux_timeline_for_kind(kind: AuxSectionKind, section: &AuxSection) -> Option<AuxTimeline> {
    match kind {
        AuxSectionKind::PromotionBannerPaths => build_promotion_timeline(section),
        _ => build_generic_aux_timeline(section),
    }
}

fn build_promotion_timeline(section: &AuxSection) -> Option<AuxTimeline> {
    if section.records.is_empty() {
        return None;
    }
    let mut cursor = 0.0f32;
    let mut phases = Vec::new();
    let mut hold_position = (
        section.records[0].origin_x as f32,
        section.records[0].origin_y as f32,
    );
    for (idx, record) in section.records.iter().enumerate() {
        let delay = promotion_segment_delay(record);
        if delay > 0.0 {
            phases.push(TimelinePhase {
                start: cursor,
                duration: delay,
                kind: TimelinePhaseKind::Gap {
                    record_index: idx,
                    hold_position,
                },
            });
            cursor += delay;
        }

        let duration = promotion_segment_duration(record).max(1.0);
        phases.push(TimelinePhase {
            start: cursor,
            duration,
            kind: TimelinePhaseKind::Motion { record_index: idx },
        });
        cursor += duration;
        hold_position = (record.target_x as f32, record.target_y as f32);
    }

    if phases.is_empty() {
        return None;
    }

    Some(AuxTimeline {
        phases,
        total_duration: cursor.max(1.0),
    })
}

fn build_generic_aux_timeline(section: &AuxSection) -> Option<AuxTimeline> {
    if section.records.is_empty() {
        return None;
    }
    let mut cursor = 0.0f32;
    let mut phases = Vec::new();
    let mut hold_position = (
        section.records[0].origin_x as f32,
        section.records[0].origin_y as f32,
    );
    for (idx, record) in section.records.iter().enumerate() {
        let delay = if record.timer_primary > 0 {
            record.timer_primary as f32
        } else {
            0.0
        };
        if delay > 0.0 {
            phases.push(TimelinePhase {
                start: cursor,
                duration: delay,
                kind: TimelinePhaseKind::Gap {
                    record_index: idx,
                    hold_position,
                },
            });
            cursor += delay;
        }

        let mut duration = if record.timer_secondary != 0 {
            record.timer_secondary.abs() as f32
        } else {
            estimate_motion_duration(record)
        };
        if duration < 1.0 {
            duration = 1.0;
        }
        phases.push(TimelinePhase {
            start: cursor,
            duration,
            kind: TimelinePhaseKind::Motion { record_index: idx },
        });
        cursor += duration;
        hold_position = (record.target_x as f32, record.target_y as f32);
    }

    if phases.is_empty() {
        return None;
    }

    Some(AuxTimeline {
        phases,
        total_duration: cursor.max(1.0),
    })
}

fn promotion_segment_delay(record: &AuxRecord) -> f32 {
    if record.timer_primary > 0 {
        record.timer_primary as f32
    } else {
        0.0
    }
}

fn promotion_segment_duration(record: &AuxRecord) -> f32 {
    if record.timer_secondary != 0 {
        record.timer_secondary.abs() as f32
    } else if record.timer_primary < 0 {
        record.timer_primary.abs() as f32
    } else {
        estimate_motion_duration(record)
    }
}

fn estimate_motion_duration(record: &AuxRecord) -> f32 {
    let dx = (record.target_x - record.origin_x).abs() as f32;
    let dy = (record.target_y - record.origin_y).abs() as f32;
    let vx = record.velocity_x.abs() as f32;
    let vy = record.velocity_y.abs() as f32;

    let mut estimate = 0.0f32;
    if vx > 0.0 {
        estimate = estimate.max(dx / vx);
    }
    if vy > 0.0 {
        estimate = estimate.max(dy / vy);
    }

    if estimate.is_finite() && estimate > 0.5 {
        estimate
    } else {
        30.0
    }
}

fn sample_aux_timeline(
    timeline: &AuxTimeline,
    section: &AuxSection,
    playhead: f32,
) -> Option<AuxPlaybackSample> {
    if timeline.phases.is_empty() {
        return None;
    }
    let clamped = playhead.clamp(0.0, timeline.total_duration);
    for phase in &timeline.phases {
        let end = phase.start + phase.duration;
        if clamped < phase.start {
            continue;
        }
        if clamped <= end {
            let elapsed = (clamped - phase.start).max(0.0);
            return match &phase.kind {
                TimelinePhaseKind::Gap {
                    record_index,
                    hold_position,
                } => Some(AuxPlaybackSample {
                    record_index: *record_index,
                    position: *hold_position,
                    is_gap: true,
                }),
                TimelinePhaseKind::Motion { record_index } => section
                    .records
                    .get(*record_index)
                    .map(|record| AuxPlaybackSample {
                        record_index: *record_index,
                        position: sample_motion_position(record, elapsed, phase.duration),
                        is_gap: false,
                    }),
            };
        }
    }

    section.records.last().map(|record| AuxPlaybackSample {
        record_index: section.records.len().saturating_sub(1),
        position: (record.target_x as f32, record.target_y as f32),
        is_gap: false,
    })
}

fn sample_motion_position(record: &AuxRecord, elapsed: f32, duration: f32) -> (f32, f32) {
    let mut x = record.origin_x as f32;
    let mut y = record.origin_y as f32;
    if record.velocity_x == 0 && record.velocity_y == 0 {
        let progress = if duration > 0.0 {
            (elapsed / duration).clamp(0.0, 1.0)
        } else {
            1.0
        };
        x = egui::lerp(record.origin_x as f32..=record.target_x as f32, progress);
        y = egui::lerp(record.origin_y as f32..=record.target_y as f32, progress);
    } else {
        x += record.velocity_x as f32 * elapsed;
        y += record.velocity_y as f32 * elapsed;
        x = clamp_axis(record.origin_x as f32, record.target_x as f32, x);
        y = clamp_axis(record.origin_y as f32, record.target_y as f32, y);
    }
    (x, y)
}

fn clamp_axis(origin: f32, target: f32, value: f32) -> f32 {
    if (origin - target).abs() < f32::EPSILON {
        return target;
    }
    let (min, max) = if origin <= target {
        (origin, target)
    } else {
        (target, origin)
    };
    value.clamp(min, max)
}

fn wave_param_row<FGet, FSet>(
    ui: &mut egui::Ui,
    label: &str,
    wave: &mut [FormationRecord],
    getter: FGet,
    setter: FSet,
    range: RangeInclusive<i32>,
) -> bool
where
    FGet: Fn(&FormationRecord) -> i32,
    FSet: Fn(&mut FormationRecord, i32),
{
    if wave.is_empty() {
        return false;
    }
    let base = getter(&wave[0]);
    let mixed = wave.iter().any(|rec| getter(rec) != base);
    let mut value = base;
    let mut changed = false;
    ui.horizontal(|ui| {
        ui.label(label);
        let mut widget = DragValue::new(&mut value).clamp_range(range.clone());
        if mixed {
            widget = widget.custom_formatter(|v, _| format!("{v}*"));
        }
        if ui.add(widget).changed() {
            changed = true;
        }
    });
    if changed {
        for record in wave.iter_mut() {
            setter(record, value);
        }
        true
    } else {
        false
    }
}

fn wave_centroid(records: &[FormationRecord]) -> (f32, f32) {
    if records.is_empty() {
        return (0.0, 0.0);
    }
    let mut sum_x = 0.0;
    let mut sum_y = 0.0;
    for record in records {
        sum_x += record.offset_x as f32;
        sum_y += record.offset_y as f32;
    }
    let count = records.len() as f32;
    (sum_x / count, sum_y / count)
}

fn angle_between(anchor: (f32, f32), point: (f32, f32)) -> f32 {
    let dx = point.0 - anchor.0;
    let dy = point.1 - anchor.1;
    dy.atan2(dx)
}

fn distance(a: (f32, f32), b: (f32, f32)) -> f32 {
    let dx = a.0 - b.0;
    let dy = a.1 - b.1;
    (dx * dx + dy * dy).sqrt()
}

fn rotate_around(point: (f32, f32), anchor: (f32, f32), radians: f32) -> (f32, f32) {
    let translated_x = point.0 - anchor.0;
    let translated_y = point.1 - anchor.1;
    let cos = radians.cos();
    let sin = radians.sin();
    let rotated_x = translated_x * cos - translated_y * sin;
    let rotated_y = translated_x * sin + translated_y * cos;
    (rotated_x + anchor.0, rotated_y + anchor.1)
}

fn scale_from(point: (f32, f32), anchor: (f32, f32), scale: f32) -> (f32, f32) {
    let translated_x = point.0 - anchor.0;
    let translated_y = point.1 - anchor.1;
    (
        translated_x * scale + anchor.0,
        translated_y * scale + anchor.1,
    )
}

fn distance_to_segment(a: Pos2, b: Pos2, p: Pos2) -> f32 {
    let ab = b - a;
    let ap = p - a;
    let len_sq = ab.length_sq();
    let t = if len_sq > 0.0 {
        ap.dot(ab) / len_sq
    } else {
        0.0
    };
    let t_clamped = t.clamp(0.0, 1.0);
    let closest = a + ab * t_clamped;
    closest.distance(p)
}

struct CanvasTransform {
    rect: egui::Rect,
    pad: f32,
    min_x: f32,
    min_y: f32,
    scale_x: f32,
    scale_y: f32,
}

impl CanvasTransform {
    fn new(rect: egui::Rect, pad: f32, min_x: f32, min_y: f32, scale_x: f32, scale_y: f32) -> Self {
        Self {
            rect,
            pad,
            min_x,
            min_y,
            scale_x,
            scale_y,
        }
    }

    fn project(&self, x: f32, y: f32) -> Pos2 {
        let px = self.rect.left() + self.pad + (x - self.min_x) * self.scale_x;
        let py = self.rect.bottom() - self.pad - (y - self.min_y) * self.scale_y;
        Pos2::new(px, py)
    }

    fn unproject(&self, pos: Pos2) -> (f32, f32) {
        let x = ((pos.x - (self.rect.left() + self.pad)) / self.scale_x) + self.min_x;
        let y = ((self.rect.bottom() - self.pad - pos.y) / self.scale_y) + self.min_y;
        (x, y)
    }
}
#[derive(Debug, Clone, Copy)]
enum MirrorAxis {
    Horizontal,
    Vertical,
}

fn wave_count(section: &FormationSection) -> usize {
    if section.records.is_empty() {
        0
    } else {
        (section.records.len() + FORMATION_ROW_SIZE - 1) / FORMATION_ROW_SIZE
    }
}

fn wave_range(section: &FormationSection, wave_index: usize) -> Option<(usize, usize)> {
    let start = wave_index.checked_mul(FORMATION_ROW_SIZE)?;
    if start >= section.records.len() {
        return None;
    }
    let end = (start + FORMATION_ROW_SIZE).min(section.records.len());
    Some((start, end))
}

fn wave_slice_mut(
    records: &mut [FormationRecord],
    wave_index: usize,
) -> Option<&mut [FormationRecord]> {
    let start = wave_index.checked_mul(FORMATION_ROW_SIZE)?;
    if start >= records.len() {
        return None;
    }
    let end = (start + FORMATION_ROW_SIZE).min(records.len());
    let (head, tail) = records.split_at_mut(end);
    let slice = &mut head[start..end];
    // tail binding keeps borrow checker happy
    let _ = tail;
    Some(slice)
}

fn wave_range_from_records(
    records: &[FormationRecord],
    wave_index: usize,
) -> Option<(usize, usize)> {
    let start = wave_index.checked_mul(FORMATION_ROW_SIZE)?;
    if start >= records.len() {
        return None;
    }
    let end = (start + FORMATION_ROW_SIZE).min(records.len());
    Some((start, end))
}
