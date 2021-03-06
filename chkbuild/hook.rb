# chkbuild/hook.rb - hook definitions
#
# Copyright (C) 2011-2012 Tanaka Akira  <akr@fsij.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above
#     copyright notice, this list of conditions and the following
#     disclaimer in the documentation and/or other materials provided
#     with the distribution.
#  3. The name of the author may not be used to endorse or promote
#     products derived from this software without specific prior
#     written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

module ChkBuild
  @build_proc_hash = {}
  def ChkBuild.define_build_proc(target_name, &block)
    raise ArgumentError, "already defined target: #{target_name.inspect}" if @build_proc_hash.include? target_name
    raise ArgumentError, "invalid target name: #{target_name.inspect}" if /\A[a-zA-Z0-9]+\z/ !~ target_name
    @build_proc_hash[target_name] = block
  end
  def ChkBuild.fetch_build_proc(target_name)
    @build_proc_hash.fetch(target_name)
  end

  @title_hook_hash = {}
  def ChkBuild.lazy_init_title_hook(target_name)
    if !@title_hook_hash.include?(target_name)
      @title_hook_hash[target_name] = []
      init_default_title_hooks(target_name)
    end
  end
  def ChkBuild.define_title_hook(target_names, secname, &block)
    target_names = [target_names] unless Array === target_names
    target_names.each {|t|
      lazy_init_title_hook(t)
      @title_hook_hash[t] << [secname, block]
    }
  end
  def ChkBuild.fetch_title_hook(target_name)
    lazy_init_title_hook(target_name)
    @title_hook_hash.fetch(target_name)
  end

  def ChkBuild.init_default_title_hooks(target_name)
    define_title_hook(target_name, 'success') {|title, log|
      title.update_title(:status) {|val| 'success' if !val }
    }
    define_title_hook(target_name, 'failure') {|title, log|
      title.update_title(:status) {|val|
        if !val
          line = /\n/ =~ log ? $` : log
          line = line.strip
          line if !line.empty?
        end
      }
    }
    define_title_hook(target_name, nil) {|title, logfile|
      num_warns = 0
      logfile.each_line {|line|
        line.scan(/warn/i) {
          num_warns += 1
        }
      }
      title.update_title(:warn) {|val| "#{num_warns}W" } if 0 < num_warns
    }
    define_title_hook(target_name, 'dependencies') {|title, log|
      dep_versions = []
      title.logfile.dependencies.each {|suffixed_name, time, ver|
        dep_versions << "(#{ver})"
      }
      title.update_title(:dep_versions, dep_versions)
    }
  end

  @failure_hook_hash = {}
  def ChkBuild.lazy_init_failure_hook(target_name)
    @failure_hook_hash[target_name] ||= []
  end
  def ChkBuild.define_failure_hook(target_names, secname, &block)
    target_names = [target_names] unless Array === target_names
    target_names.each {|target_name|
      lazy_init_failure_hook(target_name)
      @failure_hook_hash[target_name] << [secname, block]
    }
  end
  def ChkBuild.fetch_failure_hook(target_name)
    lazy_init_failure_hook(target_name)
    @failure_hook_hash.fetch(target_name)
  end

  @diff_preprocess_hook_hash = {}
  def ChkBuild.lazy_init_diff_preprocess_hook(target_name)
    if !@diff_preprocess_hook_hash.include?(target_name)
      @diff_preprocess_hook_hash[target_name] = []
      init_default_diff_preprocess_hooks(target_name)
    end
  end
  def ChkBuild.define_diff_preprocess_hook(target_names, &block)
    target_names = [target_names] unless Array === target_names
    target_names.each {|target_name|
      lazy_init_diff_preprocess_hook(target_name)
      @diff_preprocess_hook_hash[target_name] << block
    }
  end
  def ChkBuild.fetch_diff_preprocess_hook(target_name)
    lazy_init_diff_preprocess_hook(target_name)
    @diff_preprocess_hook_hash.fetch(target_name)
  end

  def ChkBuild.define_diff_preprocess_gsub_state(target_names, pat, &block)
    target_names = [target_names] unless Array === target_names
    target_names.each {|t|
      define_diff_preprocess_hook(t) {|line, state|
        line.gsub(pat) { yield $~, state }
      }
    }
  end
  def ChkBuild.define_diff_preprocess_gsub(target_names, pat, &block)
    target_names = [target_names] unless Array === target_names
    target_names.each {|t|
      define_diff_preprocess_hook(t) {|line, state| line.gsub(pat) { yield $~ } }
    }
  end

  CHANGE_LINE_PAT = /^((ADD|DEL|CHG) .*\t.*->.*|COMMIT .*|last commit:)\n/
  CHANGE_LINE_PAT2 = /^(LASTLOG .*|DIRECTORY .*|FILE .*|LASTCOMMIT .*|GITOUT .*|GITERR .*|SVNOUT .*|CVSOUT .*|CVSERR .*)\n/

  def ChkBuild.init_default_diff_preprocess_hooks(target_name)
    define_diff_preprocess_gsub(target_name, / # \d{4,}-\d\d-\d\dT\d\d:\d\d:\d\d[-+]\d\d:\d\d$/) {|match|
      ' # <time>'
    }
    define_diff_preprocess_gsub(target_name, CHANGE_LINE_PAT) {|match| '' }
    define_diff_preprocess_gsub(target_name, CHANGE_LINE_PAT2) {|match| '' }
    define_diff_preprocess_gsub(target_name, /timeout: the process group \d+ is alive/) {|match|
      "timeout: the process group <pgid> is alive"
    }
    define_diff_preprocess_gsub(target_name, /some descendant process in process group \d+ remain/) {|match|
      "some descendant process in process group <pgid> remain"
    }
    define_diff_preprocess_gsub(target_name, /^elapsed [0-9.]+s.*/) {|match|
      "<elapsed time>"
    }

    # Name:   ruby
    # State:  R (running)
    # Tgid:   11217
    # Pid:    11217
    # PPid:   11214
    # TracerPid:      0
    # Uid:    1000    1000    1000    1000
    # Gid:    1000    1000    1000    1000
    # FDSize: 64
    # Groups: 4 20 24 46 111 119 122 1000
    # VmPeak:    79108 kB
    # VmSize:    79108 kB
    # VmLck:         0 kB
    # VmHWM:     28700 kB
    # VmRSS:     28700 kB
    # VmData:    26544 kB
    # VmStk:       136 kB
    # VmExe:      2192 kB
    # VmLib:      4416 kB
    # VmPTE:       168 kB
    # VmSwap:        0 kB
    # Threads:        2
    # SigQ:   0/16382
    # SigPnd: 0000000000000000
    # ShdPnd: 0000000000000000
    # SigBlk: 0000000000000000
    # SigIgn: 0000000000000000
    # SigCgt: 0000000182007e47
    # CapInh: 0000000000000000
    # CapPrm: 0000000000000000
    # CapEff: 0000000000000000
    # CapBnd: ffffffffffffffff
    # Cpus_allowed:   1
    # Cpus_allowed_list:      0
    # Mems_allowed:   00000000,00000001
    # Mems_allowed_list:      0
    # voluntary_ctxt_switches:        4285
    # nonvoluntary_ctxt_switches:     6636
    #
    # SleepAVG:      80%
    #
    define_diff_preprocess_gsub(target_name,
      /^(Tgid|Pid|PPid|SleepAVG|VmPeak|VmSize|VmLck|VmHWM|VmRSS|VmData|VmStk|VmExe|VmLib|VmPTE|VmSwap|SigQ|voluntary_ctxt_switches|nonvoluntary_ctxt_switches):[ \t]*\d+/) {|match|
      "#{match[1]}: <nnn>"
    }

    # StaBrk:       00606000 kB
    # Brk:  05cbb000 kB
    # StaStk:       7fffe9567f90 kB
    define_diff_preprocess_gsub(target_name, /^(StaBrk|Brk|StaStk):[ \t]*[0-9a-f]+/) {|match|
      "#{match[1]}: <nnn>"
    }

    # cpu MHz       : 800.000
    # bogomips      : 1596.02
    ChkBuild.define_diff_preprocess_gsub(target_name, /^(cpu MHz|bogomips)(\t*): [\d.]+/) {|match|
      "#{match[1]}#{match[2]}: <nnn>"
    }

    # delete trailing spaces.
    ChkBuild.define_diff_preprocess_gsub(target_name, /[ \t]+$/) {|match|
      ""
    }

    # svn info prints the last revision in the whole repository
    # which can be different from the last changed revision.
    # Revision: 26147
    ChkBuild.define_diff_preprocess_gsub(target_name, /^Revision: \d+/) {|match|
      "Revision: <rev>"
    }

    # svn info prints the last changed revision.
    # Last Changed Author: nobu
    # Last Changed Rev: 29180
    # Last Changed Date: 2010-09-04 10:41:04 +0900 (Sat, 04 Sep 2010)
    ChkBuild.define_diff_preprocess_gsub(target_name, /^Last Changed Author: (.*)/) {|match|
      "Last Changed Author: <author>"
    }
    ChkBuild.define_diff_preprocess_gsub(target_name, /^Last Changed Rev: (.*)/) {|match|
      "Last Changed Rev: <rev>"
    }
    ChkBuild.define_diff_preprocess_gsub(target_name, /^Last Changed Date: (.*)/) {|match|
      "Last Changed Date: <date>"
    }


  end

  @diff_preprocess_sort_patterns_hash = {}
  def ChkBuild.define_diff_preprocess_sort(target_name, pat)
    @diff_preprocess_sort_patterns_hash[target_name] ||= []
    @diff_preprocess_sort_patterns_hash[target_name] << pat
  end
  def ChkBuild.diff_preprocess_sort_pattern(target_name)
    if !@diff_preprocess_sort_patterns_hash.include?(target_name)
      nil
    else
      /\A#{Regexp.union(*@diff_preprocess_sort_patterns_hash[target_name])}/
    end
  end

  @file_changes_viewer_hash = {}
  def ChkBuild.define_file_changes_viewer(reptype, pat, &block)
    @file_changes_viewer_hash[reptype] ||= []
    @file_changes_viewer_hash[reptype] << [pat, block]
  end
  def ChkBuild.find_file_changes_viewer(reptype, reploc)
    assoc = @file_changes_viewer_hash[reptype]
    return nil if !assoc
    assoc.each {|pat, block|
      if pat.respond_to? :match
        m = pat.match(reploc)
      else
        m = pat == reploc
      end
      if m
        return block.call(m, reptype, pat, reploc)
      end
    }
    nil
  end
end

