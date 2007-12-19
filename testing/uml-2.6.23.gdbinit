# These two gdb user defined commands might help you to unterstand
# kernel lockups. 
# Use these functions on a GDB running User Mode Linux in SKAS mode.
#
# You can load this file into GDB by using the 'source' command,
# or simply put it into your .gdbinit
#
# This works in my environment of (Debian Woody 3.0):
#  binutils         2.12.90.0.1-4
#  gcc              2.95.4-14
#  gdb              5.2.cvs20020401-6
#  linux            2.6.1
#  uml              some patches :)
#
# I experienced serious troubles using Debian Sid Packages...
#  * gdb crashing
#  * gdb printing bogus stack traces
#  * uml kernel crashing in strange places 
#  * strange behaviour
#
# -Philipp

define lx-container-of
  set $rv = (($arg1 *)((char *)($arg0)-(unsigned long)(&((($arg1 *)0)->$arg2))))
end

define lx-container-of-struct
  set $rv = ((struct $arg1 *)((char *)($arg0)-(unsigned long)(&(((struct $arg1 *)0)->$arg2))))
end

#define linux-mod-helper
#  lx-container-of-struct modules->next module list
#  p $rv->module_core
#end

define linux-mod-helper
  lx-container-of-struct modules module list
  set $m = $rv
  set $lh = $rv
  set $cont = 1
  while $cont
     printf "%p %s\n",$m->module_core,$m->name
     lx-container-of-struct $m->list.next module list
     set $m = $rv
     if $m == $lh
       set $cont = 0
     end
  end
end

# for old kernels, worked with linux-2.6.1
#define linux-ps
#  set $ps_ph_i = 1<<pidhash_shift
#  printf "---TASK---  -PID-  --------COMM----------\n"
#  while $ps_ph_i > 0
#    set $ps_ph_i = $ps_ph_i - 1
#    set $ps_plist = &pid_hash[0][$ps_ph_i]
#    set $ps_pitem = $ps_plist->next
#    while $ps_pitem != $ps_plist
#      lx-container-of-struct $ps_pitem pid hash_chain
#      set $ps_pid = $rv
#      set $ps_h = $ps_pid->task_list.next
#      lx-container-of-struct $ps_h task_struct pids[0].pid_chain
#      set $ps_t = $rv
#      printf "%8p  %-5d  %-20s\n", $ps_t, $ps_pid->nr, $ps_t->comm
#      set $ps_pitem = $ps_pitem->next
#    end
#  end
#end

define linux-ps
  set $ps_ph_i = 1<<pidhash_shift
  printf "---TASK---  -PID-  --------COMM----------\n"
  while $ps_ph_i > 0
    set $ps_ph_i = $ps_ph_i - 1
#    set $ps_pitem = pid_hash[0][$ps_ph_i]->first
#    set $ps_pitem = pid_hash[$ps_ph_i]->first
    set $ps_pitem = *(struct task_struct*)cpu_tasks->task
    while $ps_pitem != 0
      lx-container-of-struct $ps_pitem pid pid_chain
      set $ps_pid = $rv
#      set $ps_h = $ps_pid->pid_list.next
printf "%p" $ps_pid
      set $ps_h = $ps_pid->next
      lx-container-of-struct $ps_h task_struct pids[0].pid_list
      set $ps_t = $rv
      if $ps_pid->nr != 0
        printf "%8p  %-5d  %-20s\n", $ps_t, $ps_pid->nr, $ps_t->comm
      end
      set $ps_pitem = $ps_pitem->next
    end
  end
end

document linux-ps
  linux-ps lists all tasks on the system. 
  Also have a look at linux-bt.
end

define linux-bt
  set $bt_switch_buf = ((struct task_struct*)$arg0)->thread.mode.skas.switch_buf
  set $bt_ebp = $bt_switch_buf[0]->__ebp
  set $bt_i = 0
  printf "-#-  ---EBP----  ---EIP----    ---------FUNCTION---------\n"
  while $bt_i < 32
    set $bt_eip = ((unsigned long*)$bt_ebp)[1]
    if $bt_eip < 0x00100000
      set $bt_i = 32
    else 
      printf "#%-2d  0x%8x  0x%8x in ", $bt_i, $bt_ebp, $bt_eip
      info symbol $bt_eip
      set $bt_ebp = ((unsigned long*)$bt_ebp)[0]
      set $bt_i = $bt_i + 1
    end
  end
end

document linux-bt
  linux-bt takes the address of a task_struct as argument,
  and prints the stack back trace of that task.
  You might use linux-ps to find the addresses of all available
  tasks on the system
end

define linux-page-address
  printf "0x%08x\n", ((((struct page*)$arg0) - mem_map) << 12) + uml_physmem
end

document linux-page-address
  linux-page-address prints the virtual address of a struct page* 
  pointer. Equivalent to the result of kmap(page). 
  Only works on a LOWMEM UML ( is HIGHMEM possible in UML ? ).
end

define drbd-resync-show
  set $sr_base = ((struct Drbd_Conf *)$arg0)->resync
  lru-show $sr_base
end

define drbd-al-show
  set $sa_base = ((struct Drbd_Conf *)$arg0)->act_log
  lru-show $sa_base
end

define lru-show
  set $ls_nr=((struct lru_cache *)$arg0)->nr_elements
  set $ls_elements=(void *) (((struct lru_cache *)$arg0)->slot + $ls_nr)
  set $ls_esize=((struct lru_cache *)$arg0)->element_size

  printf "-#-  -TABLE-#-  -EXTENT-   LRU LIST\n"
  set $ls_le=((struct lru_cache *)$arg0)->lru->next
  set $ls_i=0
  while $ls_le != &((struct lru_cache *)$arg0)->lru && $ls_i < $ls_nr
    lx-container-of-struct $ls_le lc_element list
    set $ls_e = $rv
    set $ls_en = ((void*)$ls_e-$ls_elements)/$ls_esize
    printf "%3d  %8d  %8d\n", $ls_i, $ls_en, $ls_e->lc_number
    set $ls_i = $ls_i + 1
    set $ls_le = $ls_le->next    
  end
  printf "%d %p %d\n",$ls_nr,$ls_elements,$ls_esize
  printf "-#-  ---ADDR---  -EXTENT-  -REFCNT-  -HASH-NEXT-   TABLE\n"
  set $ls_i=0
  while $ls_i < $ls_nr
    set $ls_element = (struct lc_element *)($ls_elements + $ls_i * $ls_esize)
    printf "%3d  0x%8x  %8d ", $ls_i, $ls_element, $ls_element->lc_number
    printf " %8d ", $ls_element->refcnt
    if $ls_element->colision.next
      printf "  %3d", ((void *)$ls_element->colision.next - $ls_elements)/$ls_esize
    end
    printf "\n"
    set $ls_i = $ls_i + 1    
  end
end

define drbd-add-symbol-file-drbd08
  set $m = modules->next
  while $m != &modules
    lx-container-of-struct ($m) module list
    if ($rv->name[0] == 'd' && $rv->name[1] == 'r' && $rv->name[2] == 'b' && $rv->name[3] == 'd' && $rv->name[4] == 0)
    	# p *$rv
	add-symbol-file ~johannes/drbd/git/drbd-8.2/drbd/drbd.ko $rv->module_core
	set $m = modules->prev
    end
    set $m = $m->next
  end
end


#
# These macros should work with the 2.6.23 kernel.
# They were written from scratch by Joe Object.
#
# Most likely returns a pointer to the swapper (PID 0) process.
# This was found by trial-and-error so don't rely on it.
# In general functions return values by setting the $rv 
# variable.
#

define get-swapper
	set $rv=((struct task_struct*)cpu_tasks->task)
end

#
# get-next-task <task-struct-pointer>
#
define get-next-task
	set $offset = (unsigned long)&((struct task_struct*)0)->tasks
	set $rv = ((struct task_struct*)(((char*)(*$arg0).tasks.prev)-$offset))
end

#
# This prints all processes.
#
define print-processes
	get-swapper
	set $swapper = $rv
	printf "%8d %p %s\n", $swapper->pid, $swapper, $swapper->comm
	get-next-task $swapper
	set $next = $rv
	while $next != $swapper
		printf "%8d %p %s\n", $next->pid, $next, $next->comm
		get-next-task $next
		set $next = $rv
	end
end
