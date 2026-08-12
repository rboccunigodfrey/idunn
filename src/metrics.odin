package idunn

import "base:runtime"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

DebugCheckpointType :: enum {
	FrameStart,
	CameraUpdate,
	MovementUpdate,
	PhysicsUpdate,
	Render,
	Blit,
	Draw,
}

DebugCheckpointDisplayInfo := [DebugCheckpointType]struct {
	label: string,
	color: rl.Color,
} {
	.FrameStart     = {"frame_start", rl.RED},
	.CameraUpdate   = {"camera_update", rl.ORANGE},
	.MovementUpdate = {"movement_update", rl.YELLOW},
	.PhysicsUpdate  = {"physics_update", rl.GREEN},
	.Render         = {"render", rl.BLUE},
	.Blit           = {"blit", rl.PURPLE},
	.Draw           = {"draw", rl.VIOLET},
}

DebugMetricType :: enum {
	ArenaAllocations,
	BytesAllocated,
	TSC,
	NSec,
	Monotonic,
}

DebugMetricDisplayInfo := [DebugMetricType]struct {
	label:       string,
	scale:       f32,
	axis_scale:  f32,
	scale_label: string,
	color:       rl.Color,
} {
	.ArenaAllocations = {"arena_allocations (#)", 10, 0.1, "", rl.BLACK},
	.BytesAllocated   = {"bytes_allocated (b)", 1e-5, 0.1, "M", rl.BLACK},
	.TSC              = {"cpu_time (cycles)", 1e-6, 1, "M", rl.BLACK},
	.NSec             = {"clock_time (ms)", 1e-6, 1, "", rl.BLACK},
	.Monotonic        = {"monotonic_time (ms)", 1e-6, 1, "", rl.BLACK},
}

DebugMetrics :: struct #raw_union {
	using _: struct {
		aallocs:  i64,
		balloced: i64,
		tsc:      i64,
		nsec:     i64,
		mono:     i64,
	},
	e:       [len(DebugMetricType)]i64,
}

metrics_now :: proc(frame_count: i32, arena: MemoryArena) -> (result: DebugMetrics) {
	result.aallocs = i64(arena.allocation_count)
	result.balloced = i64(arena.bytes_allocated)
	result.nsec = time.to_unix_nanoseconds(time.now())
	result.mono = time.tick_now()._nsec
	result.tsc = runtime.read_cycle_counter()

	return
}

metrics_diff :: proc(ts1: DebugMetrics, ts2: DebugMetrics) -> (result: DebugMetrics) {
	result.e = ts1.e - ts2.e
	return
}
metrics_sum :: proc(ts1: DebugMetrics, ts2: DebugMetrics) -> (result: DebugMetrics) {
	result.e = ts1.e + ts2.e
	return
}

DebugFrame :: struct {
	checkpoints: struct #raw_union {
		using _: struct {
			frame_start:     DebugMetrics,
			camera_update:   DebugMetrics,
			movement_update: DebugMetrics,
			physics_update:  DebugMetrics,
			render:          DebugMetrics,
			blit:            DebugMetrics,
		},
		e:       [len(DebugCheckpointType)]DebugMetrics,
	},
	total_frame: DebugMetrics,
}

DebugInfo :: struct {
	frames:     [DEBUG_MAX_FRAME_COUNT]DebugFrame,
	average:    DebugFrame,
	size:       i32,
	cur_frame:  i32,
	start_time: DebugMetrics,
}

DEBUG_log_checkpoint :: proc(
	info: ^DebugInfo,
	type: DebugCheckpointType,
	arena: MemoryArena,
	frame_index: i32,
) {
	when DEBUGGING {
		frame_index := frame_index % len(info.frames)
		frame := &info.frames[frame_index]
		type_index := i32(type)
		total_time := metrics_now(frame_index, arena)
		frame_time := metrics_diff(total_time, info.start_time)
		value :=
			type_index == 0 ? frame_time : metrics_diff(frame_time, frame.checkpoints.e[type_index - 1])
		frame.checkpoints.e[type_index] = value

		info.cur_frame = frame_index
		if type_index == len(frame.checkpoints.e) - 1 {
			if info.size < len(info.frames) do info.size += 1
			frame.total_frame = frame_time
		}
	}
}

DEBUG_display_overlay :: proc(info: ^DebugInfo, enabled_metrics: [$N]DebugMetricType) {
	when DEBUGGING {
		opacity: f32 = 0.5 //f32(info.size) / f32(info.cur_frame - frame_index + 1)
		v_spacing: i32 = 250


		for em_i_neg in 0 ..< N {
			em_i := N - em_i_neg - 1
			metric_type := enabled_metrics[em_i_neg]
			metric_display_info := DebugMetricDisplayInfo[metric_type]

			ct_i := i32(metric_type)
			v_offset := PIXEL_COUNT_Y * PIXEL_SIZE - v_spacing * i32(em_i)
			metric_v_offset := v_offset
			for f_i in 0 ..< info.size {
				frame_index := info.cur_frame - (info.size - 1) + f_i
				if frame_index < 0 do frame_index += len(info.frames)
				frame := info.frames[frame_index]

				initial_v_offset := metric_v_offset
				for c_i in 0 ..< len(DebugCheckpointType) {

					checkpoint_type := DebugCheckpointType(c_i)
					checkpoint_value := frame.checkpoints.e[c_i].e[ct_i]
					info.average.checkpoints.e[c_i].e[ct_i] += checkpoint_value
					display_info := DebugCheckpointDisplayInfo[checkpoint_type]
					v_offset =
						initial_v_offset - i32(f32(checkpoint_value) * metric_display_info.scale)
					rl.DrawLine(
						f_i,
						initial_v_offset,
						f_i,
						v_offset,
						rl.ColorAlpha(display_info.color, opacity),
					)
					initial_v_offset = v_offset
				}

				info.average.total_frame.e += frame.total_frame.e

				rl.DrawText(
					strings.clone_to_cstring(metric_display_info.label, context.temp_allocator),
					40,
					metric_v_offset - 15,
					15,
					metric_display_info.color,
				)

				interval: i32 : 20
				for i in 0 ..< 10 {
					axis_label_offset := interval * i32(i)
					axis_label: [16]u8
					sb := strings.builder_from_bytes(axis_label[:])
					axis_label_value := f32(axis_label_offset) * metric_display_info.axis_scale
					strings.write_int(&sb, int(axis_label_value), 10)
					strings.write_string(&sb, metric_display_info.scale_label)
					axis_label_pos_y := metric_v_offset - axis_label_offset
					rl.DrawText(
						strings.to_cstring(&sb),
						10,
						axis_label_pos_y,
						13,
						metric_display_info.color,
					)
					rl.DrawLine(0, axis_label_pos_y, len(info.frames), axis_label_pos_y, rl.BLACK)
				}
			}

			info.average.total_frame.e[ct_i] /= i64(info.size)

			total_average_pixel_height: i32 = 500
			total_average_pixel_width: i32 = 20
			total_average_height := i32(info.average.total_frame.e[ct_i])
			ratio := f32(total_average_pixel_height) / f32(total_average_height)


			rl.DrawLine(
				len(info.frames) + 20,
				metric_v_offset - total_average_pixel_height,
				len(info.frames) + 20 + total_average_pixel_width,
				metric_v_offset - total_average_pixel_height,
				rl.WHITE,
			)

			accum := metric_v_offset
			for c_i in 0 ..< len(DebugCheckpointType) {
				checkpoint_type := DebugCheckpointType(c_i)
				checkpoint_display_info := DebugCheckpointDisplayInfo[checkpoint_type]
				info.average.checkpoints.e[c_i].e[ct_i] /= i64(info.size)
				checkpoint_value := info.average.checkpoints.e[c_i].e[ct_i]
				metric_average_height := i32(checkpoint_value)
				pixel_height := i32(f32(metric_average_height) * ratio)


				rl.DrawRectangle(
					len(info.frames) + 20,
					accum - pixel_height,
					total_average_pixel_width,
					pixel_height,
					checkpoint_display_info.color,
				)

				label_buf: [16]u8
				sb := strings.builder_from_bytes(label_buf[:])
				strings.write_string(&sb, checkpoint_display_info.label)
				strings.write_string(&sb, " (")
				strings.write_int(&sb, int(f32(checkpoint_value) * ratio * 100))
				strings.write_string(&sb, "%)")

				if pixel_height > 20 do rl.DrawText(strings.to_cstring(&sb), len(info.frames) + 40, accum - 15, 15, checkpoint_display_info.color)
				accum -= pixel_height
			}
		}


		v_spacing_legend: i32 = 15
		for neg_legend_i in 0 ..< len(DebugCheckpointType) {
			legend_i := len(DebugCheckpointType) - neg_legend_i - 1
			checkpoint_type := DebugCheckpointType(neg_legend_i)
			legend_display_info := DebugCheckpointDisplayInfo[checkpoint_type]
			legend_v_offset := PIXEL_COUNT_Y * PIXEL_SIZE - v_spacing_legend * i32(legend_i + 1)
			rl.DrawText(
				strings.clone_to_cstring(legend_display_info.label, context.temp_allocator),
				len(info.frames) + 60,
				legend_v_offset,
				13,
				legend_display_info.color,
			)
		}


		rl.DrawFPS(40, 40)
	}
}
