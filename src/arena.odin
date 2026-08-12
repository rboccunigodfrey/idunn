package idunn

import "core:mem"
MemoryArena :: struct {
	data:               [^]u8,
	allocation_count:   int,
	bytes_allocated:    int,
	deallocation_count: int,
	bytes_deallocated:  int,
	size:               int,
	capacity:           int,
}

arena_alloc_size :: proc(arena: ^MemoryArena, size: int) -> rawptr {
	assert(arena.size + size <= arena.capacity, "[FATAL] Arena out-of-memory!")
	ptr := mem.ptr_offset(arena.data, arena.size)
	arena.size += size
	arena.allocation_count += 1
	arena.bytes_allocated += size

	return ptr
}

arena_alloc_struct :: proc(arena: ^MemoryArena, $T: typeid) -> ^T {
	return cast(^T)arena_alloc_size(arena, size_of(T))
}

arena_alloc_slice :: proc(arena: ^MemoryArena, $AT: typeid/[]$T, size: int) -> []T {
	return cast([]T)(cast([^]T)arena_alloc_size(arena, size_of(T) * size))[0:size]
}

arena_make :: proc {
	arena_alloc_size,
	arena_alloc_struct,
	arena_alloc_slice,
}

initialize_arena_with_backing :: proc(buffer: [^]u8, size: int) -> MemoryArena {
	return MemoryArena{data = buffer, capacity = size}
}

initialize_arena_from_size :: proc(size: int) -> MemoryArena {
	buffer := make([^]u8, size)

	return MemoryArena{data = buffer, capacity = size}
}

initialize_arena :: proc {
	initialize_arena_from_size,
	initialize_arena_with_backing,
}

arena_clear :: proc(arena: ^MemoryArena) {
	arena.size = 0
}
