package fifo

import "core:sync"

Fifo :: struct($T: typeid) {
	buf: []T,
	shared_mutex_fifo: ^Fifo(T),
	mutex_head: sync.Mutex,
	mutex_tail: sync.Mutex,
	cond_add: sync.Condition,
	cond_get: sync.Condition,
	head: u16,
	tail: u16,
	_iter_head: u16,
	input_count: u8,
	is_open: bool,
}

new_fifo :: proc($T: typeid, n: u16) -> ^Fifo(T) {
	new_fifo := new(Fifo(T))
	new_fifo^ = make_fifo(T, n)
	return new_fifo
}

make_fifo :: proc($T: typeid, n: u16) -> Fifo(T) {
	new_fifo := Fifo(T) {
		buf = make([]T, n),
		is_open = true,
	}
	sync.mutex_init(&new_fifo.mutex_head)
	sync.mutex_init(&new_fifo.mutex_tail)
	sync.condition_init(&new_fifo.cond_add, &new_fifo.mutex_head)
	sync.condition_init(&new_fifo.cond_get, &new_fifo.mutex_tail)
	return new_fifo
}

destroy :: proc(f: ^Fifo($T)) {
	delete(f.buf)
	sync.mutex_destroy(&f.mutex_head)
	sync.mutex_destroy(&f.mutex_tail)
	sync.condition_destroy(&f.cond_add)
	sync.condition_destroy(&f.cond_get)
}

reset :: proc(f: ^Fifo($T)) {
	if f == nil {
		return
	}

	f.is_open = true
	f.head = 0
	f.tail = 0
	f._iter_head = 0
}

set_open :: proc(f: ^Fifo($T), is_open: bool) {
	sync.mutex_lock(&f.mutex_tail)
	sync.mutex_lock(&f.mutex_head)

	f.is_open = is_open
	sync.condition_broadcast(&f.cond_add)
	sync.condition_broadcast(&f.cond_get)
	if f.shared_mutex_fifo != nil {
		sync.mutex_lock(&f.shared_mutex_fifo.mutex_head)
		sync.condition_broadcast(&f.shared_mutex_fifo.cond_add)
		sync.mutex_unlock(&f.shared_mutex_fifo.mutex_head)
		f.shared_mutex_fifo = nil
	}

	sync.mutex_unlock(&f.mutex_tail)
	sync.mutex_unlock(&f.mutex_head)
}

peek :: proc(f: ^Fifo($T)) -> ^T {
	return &f.buf[f.tail]
}

available :: proc(f: ^Fifo($T)) -> u16 {
	n : u32 = u32(f.head - f.tail)
	if n > len(f.buf) {
		n += len(f.buf)
	}
	return n
}

is_empty :: proc(f: ^Fifo($T)) -> bool {
	return f.head == f.tail
}

is_full :: proc(f: ^Fifo($T)) -> bool {
	return (f.head + 1) % len(f.buf) == f.tail
}

set_full :: proc(f: ^Fifo($T)) {
	f.tail = 0
	f.head = u16(len(f.buf)) - 1
}

/* basically get without the get part */
consume :: proc(f: ^Fifo($T)) {
	sync.mutex_lock(&f.mutex_tail)
	_idx_adv(f, &f.tail)
	sync.codition_signal(&f.cond_get)
	sync.mutex_unlock(&f.mutex_tail)
}

get :: proc(f: ^Fifo($T)) -> ^T {
	sync.mutex_lock(&f.mutex_tail)
	data := peek(f)
	_idx_adv(f, &f.tail)
	sync.codition_signal(&f.cond_get)
	sync.mutex_unlock(&f.mutex_tail)
	return data
}

/* basically add without the add part */
advance :: proc(f: ^Fifo($T)) {
	sync.mutex_lock(&f.mutex_head)
	_idx_adv(f, &f.head)
	sync.condition_signal(&f.cond_add)
	sync.mutex_unlock(&f.mutex_head)
}

add :: proc(f: ^Fifo($T), data: T) -> ^T {
	sync.mutex_lock(&f.mutex_head)
	f.buf[f.head] = data
	_idx_adv(f, &f.head)
	sync.condition_signal(&f.cond_add)
	sync.mutex_unlock(&f.mutex_head)
}

@(private = "file")
_idx_adv :: proc(f: ^Fifo($T), idx: ^u16) {
	idx^ = (idx^ + 1) % u16(len(f.buf))
}
